<?php

namespace Tests\Feature\Inquiry;

use App\Enums\ListingStatus;
use App\Enums\UserRole;
use App\Models\Listing;
use App\Models\User;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * The one-inquiry-per-buyer-per-listing index must be addable to a database that
 * already holds duplicates, which main allowed until now. Adding a unique index
 * to such a table fails with a duplicate-entry error, so the migration resolves
 * them first — and must not delete anything while doing so.
 */
class UniqueBuyerListingMigrationTest extends TestCase
{
    use RefreshDatabase;

    private const INDEX = 'inquiries_buyer_id_listing_id_unique';

    private function migration(): object
    {
        return require database_path(
            'migrations/2026_10_30_000000_add_unique_buyer_listing_to_inquiries.php',
        );
    }

    /**
     * Put the table back to how it is on main: no unique index.
     */
    private function withoutTheIndex(): void
    {
        Schema::table('inquiries', function ($table): void {
            $table->dropUnique(self::INDEX);
        });
    }

    private function listing(User $seller): Listing
    {
        return Listing::create([
            'seller_id' => $seller->id,
            'livestock_type' => 'cattle',
            'breed' => 'Angus',
            'age_value' => 2,
            'age_unit' => 'year',
            'gender' => 'male',
            'weight_value' => 500,
            'weight_unit' => 'kg',
            'quantity' => 1,
            'asking_price' => 50000.00,
            'location' => 'Bukidnon',
            'health_status' => 'healthy',
            'vaccination' => 'up_to_date',
            'short_description' => 'Healthy Angus bull',
            'photos' => [],
            'status' => ListingStatus::Active,
        ]);
    }

    private function inquiry(User $buyer, User $seller, ?Listing $listing, string $subject): int
    {
        return DB::table('inquiries')->insertGetId([
            'buyer_id' => $buyer->id,
            'seller_id' => $seller->id,
            'listing_id' => $listing?->id,
            'subject' => $subject,
            'message' => 'Is this still available?',
            'status' => 'open',
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    #[Test]
    public function duplicates_are_kept_but_detached_so_the_index_can_be_added(): void
    {
        $this->withoutTheIndex();

        $seller = User::factory()->seller()->create(['role' => UserRole::User]);
        $ana = User::factory()->create(['role' => UserRole::User]);
        $ben = User::factory()->create(['role' => UserRole::User]);
        $first = $this->listing($seller);
        $second = $this->listing($seller);

        $anaFirst = $this->inquiry($ana, $seller, $first, 'ana 1');
        $anaDuplicate = $this->inquiry($ana, $seller, $first, 'ana 2');
        $anaThird = $this->inquiry($ana, $seller, $first, 'ana 3');
        $anaOtherListing = $this->inquiry($ana, $seller, $second, 'ana other listing');
        $benOnly = $this->inquiry($ben, $seller, $first, 'ben');

        $this->migration()->up();

        // Nothing is deleted.
        $this->assertSame(5, DB::table('inquiries')->count());

        // The earliest inquiry per buyer and listing keeps its listing.
        $this->assertSame($first->id, DB::table('inquiries')->find($anaFirst)->listing_id);
        $this->assertSame($second->id, DB::table('inquiries')->find($anaOtherListing)->listing_id);
        $this->assertSame($first->id, DB::table('inquiries')->find($benOnly)->listing_id);

        // Later duplicates are detached, with their content intact.
        foreach ([$anaDuplicate, $anaThird] as $id) {
            $row = DB::table('inquiries')->find($id);
            $this->assertNull($row->listing_id);
            $this->assertSame('Is this still available?', $row->message);
            $this->assertSame('open', $row->status);
        }

        // And the index is really there afterwards.
        $this->assertTrue(Schema::hasIndex('inquiries', self::INDEX, 'unique'));
        $this->expectException(UniqueConstraintViolationException::class);
        $this->inquiry($ana, $seller, $first, 'a new duplicate');
    }

    #[Test]
    public function inquiries_without_a_listing_are_left_alone(): void
    {
        $this->withoutTheIndex();

        $seller = User::factory()->seller()->create(['role' => UserRole::User]);
        $ana = User::factory()->create(['role' => UserRole::User]);

        // A deleted listing leaves `listing_id` NULL, and NULLs are distinct.
        $one = $this->inquiry($ana, $seller, null, 'listing deleted 1');
        $two = $this->inquiry($ana, $seller, null, 'listing deleted 2');

        $this->migration()->up();

        $this->assertSame(2, DB::table('inquiries')->count());
        $this->assertNull(DB::table('inquiries')->find($one)->listing_id);
        $this->assertNull(DB::table('inquiries')->find($two)->listing_id);
        $this->assertTrue(Schema::hasIndex('inquiries', self::INDEX, 'unique'));
    }

    #[Test]
    public function a_database_without_duplicates_is_unchanged(): void
    {
        $this->withoutTheIndex();

        $seller = User::factory()->seller()->create(['role' => UserRole::User]);
        $ana = User::factory()->create(['role' => UserRole::User]);
        $ben = User::factory()->create(['role' => UserRole::User]);
        $listing = $this->listing($seller);

        $a = $this->inquiry($ana, $seller, $listing, 'ana');
        $b = $this->inquiry($ben, $seller, $listing, 'ben');

        $this->migration()->up();

        $this->assertSame($listing->id, DB::table('inquiries')->find($a)->listing_id);
        $this->assertSame($listing->id, DB::table('inquiries')->find($b)->listing_id);
        $this->assertTrue(Schema::hasIndex('inquiries', self::INDEX, 'unique'));
    }
}
