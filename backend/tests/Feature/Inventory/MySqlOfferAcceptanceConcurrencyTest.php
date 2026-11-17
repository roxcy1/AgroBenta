<?php

namespace Tests\Feature\Inventory;

use App\Enums\ListingStatus;
use App\Enums\UserRole;
use App\Models\Inquiry;
use App\Models\Listing;
use App\Models\Offer;
use App\Models\Transaction;
use App\Models\User;
use App\Services\Offer\OfferService;
use Illuminate\Support\Facades\DB;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;
use Tests\TestCase;
use Throwable;

/**
 * Real InnoDB contention proof. It is skipped by the normal SQLite suite.
 *
 * Provision and migrate only the isolated `agrobenta_multi_quantity_test`
 * database, then opt in with `AGROBENTA_MYSQL_INVENTORY_TESTS=1`. Never point
 * this test at the application database.
 */
class MySqlOfferAcceptanceConcurrencyTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        if (getenv('AGROBENTA_MYSQL_INVENTORY_TESTS') !== '1') {
            $this->markTestSkipped('Set AGROBENTA_MYSQL_INVENTORY_TESTS=1 to run the isolated MySQL concurrency test.');
        }

        if (DB::connection()->getDriverName() !== 'mysql' ||
            DB::connection()->getDatabaseName() !== 'agrobenta_multi_quantity_test') {
            throw new RuntimeException('Expected the isolated agrobenta_multi_quantity_test MySQL database.');
        }

        foreach (['users', 'listings', 'inquiries', 'offers', 'transactions', 'activities'] as $table) {
            if (! DB::getSchemaBuilder()->hasTable($table)) {
                throw new RuntimeException('Apply migrations to the isolated MySQL test database before running this test.');
            }
        }
    }

    #[Test]
    public function simultaneous_acceptances_cannot_reserve_the_same_partial_stock(): void
    {
        if (! function_exists('pcntl_fork') || ! function_exists('stream_socket_pair')) {
            $this->markTestSkipped('The isolated test container needs pcntl and Unix socket-pair support.');
        }

        $seller = User::factory()->seller()->create([
            'role' => UserRole::User,
            'email' => 'inventory-seller-'.bin2hex(random_bytes(5)).'@agrobenta.test',
        ]);
        $buyers = [
            User::factory()->create(['role' => UserRole::User]),
            User::factory()->create(['role' => UserRole::User]),
        ];
        $listing = Listing::query()->create([
            'seller_id' => $seller->id,
            'livestock_type' => 'goat',
            'breed' => 'Native',
            'age_value' => 2,
            'age_unit' => 'year',
            'age_information' => 'known',
            'gender' => 'female',
            'weight_value' => 25,
            'weight_unit' => 'kg',
            'weight_information' => 'measured',
            'quantity' => 3,
            'total_quantity' => 3,
            'asking_price' => '2500.00',
            'location' => 'Purok 3, Barangay Poblacion, Trinidad, Bohol',
            'short_description' => 'Three goats',
            'photos' => [],
            'status' => ListingStatus::Active,
        ]);

        $offers = [];
        foreach ($buyers as $buyer) {
            $inquiry = Inquiry::query()->create([
                'buyer_id' => $buyer->id,
                'seller_id' => $seller->id,
                'listing_id' => $listing->id,
                'requested_quantity' => 2,
                'message' => 'Interested in two goats.',
                'payment_method' => 'cash',
                'collection_method' => 'farm_pickup',
                'status' => 'open',
            ]);

            $offers[] = Offer::query()->create([
                'inquiry_id' => $inquiry->id,
                'listing_id' => $listing->id,
                'seller_id' => $seller->id,
                'buyer_id' => $buyer->id,
                'proposed_amount' => '4000.00',
                'proposed_quantity' => 2,
                'status' => 'pending',
            ]);
        }

        $workers = [];
        foreach ($buyers as $index => $buyer) {
            $sockets = stream_socket_pair(STREAM_PF_UNIX, STREAM_SOCK_STREAM, STREAM_IPPROTO_IP);
            if ($sockets === false) {
                throw new RuntimeException('Could not create a MySQL concurrency worker socket.');
            }

            $pid = pcntl_fork();
            if ($pid === -1) {
                throw new RuntimeException('Could not fork a MySQL concurrency worker.');
            }

            if ($pid === 0) {
                fclose($sockets[0]);
                stream_set_timeout($sockets[1], 30);
                fread($sockets[1], 1); // release both workers at the same barrier

                try {
                    // Never use a PDO socket inherited from the parent process.
                    DB::purge('mysql');
                    DB::reconnect('mysql');

                    $accepted = app(OfferService::class)->accept(
                        (int) $offers[$index]->getKey(),
                        User::query()->findOrFail($buyer->getKey()),
                    );
                    fwrite($sockets[1], 'accepted:'.$accepted['transaction']->quantity);
                    fclose($sockets[1]);
                    exit(0);
                } catch (HttpExceptionInterface $exception) {
                    fwrite($sockets[1], 'http:'.$exception->getStatusCode());
                    fclose($sockets[1]);
                    exit(0);
                } catch (Throwable $exception) {
                    fwrite($sockets[1], 'error:'.$exception::class);
                    fclose($sockets[1]);
                    exit(1);
                }
            }

            fclose($sockets[1]);
            $workers[] = ['pid' => $pid, 'socket' => $sockets[0]];
        }

        foreach ($workers as $worker) {
            fwrite($worker['socket'], 'x');
        }

        $results = [];
        foreach ($workers as $worker) {
            $results[] = stream_get_contents($worker['socket']);
            fclose($worker['socket']);
            pcntl_waitpid($worker['pid'], $status);
            $this->assertSame(0, pcntl_wexitstatus($status));
        }

        DB::purge('mysql');
        DB::reconnect('mysql');

        sort($results);
        $this->assertSame(['accepted:2', 'http:409'], $results);
        $this->assertSame(1, Transaction::query()->where('listing_id', $listing->id)->count());
        $this->assertSame(1, (int) $listing->fresh()->quantity);
        $this->assertSame(
            1,
            Offer::query()
                ->where('listing_id', $listing->id)
                ->where('status', 'accepted')
                ->count(),
        );
    }
}
