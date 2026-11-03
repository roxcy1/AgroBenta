<?php

namespace Database\Seeders;

use App\Enums\ListingStatus;
use App\Enums\SellerCapability;
use App\Enums\TransactionStatus;
use App\Enums\UserRole;
use App\Models\Listing;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;

/**
 * Development-only demo data for the Buyer Home "Popular Livestock" ranking.
 *
 * Creates 100 completed sales across the four canonical categories — cattle 40,
 * goat 30, swine 20, carabao 10 — each against a **distinct** demo listing, so
 * the ranking reflects genuine completed-transaction counts.
 *
 * Everything it creates is identifiable and reversible:
 *  - demo accounts use the reserved `@agrobenta.test` domain and the
 *    `popular.demo.` local-part prefix;
 *  - demo listings carry the `[popular-livestock-demo]` marker in
 *    `short_description` and a deterministic `PopularDemo …` breed;
 *  - demo transactions are exactly the completed rows on those listings.
 *
 * It is idempotent: users, listings and transactions are matched by their
 * natural keys (`firstOrCreate`), so re-running it creates no duplicates. It
 * only refreshes the timestamps of its own demo transactions, keeping them
 * inside the 30-day popularity window; it never touches any other record.
 *
 * Never registered in `DatabaseSeeder`. Run it explicitly on the local
 * development database only:
 *
 *     php artisan db:seed --class=PopularLivestockDemoSeeder
 */
class PopularLivestockDemoSeeder extends Seeder
{
    private const DEMO_DOMAIN = 'agrobenta.test';

    private const EMAIL_PREFIX = 'popular.demo.';

    public const LISTING_MARKER = '[popular-livestock-demo]';

    /**
     * Target completed sales per canonical category.
     *
     * @var array<string, int>
     */
    private const TARGETS = [
        'Cattle' => 40,
        'Goat' => 30,
        'Swine' => 20,
        'Carabao' => 10,
    ];

    /**
     * Demo buyers, as [display name, email local part].
     *
     * @var list<array{0: string, 1: string}>
     */
    private const BUYERS = [
        ['Demo Buyer One', 'buyer.1'],
        ['Demo Buyer Two', 'buyer.2'],
        ['Demo Buyer Three', 'buyer.3'],
        ['Demo Buyer Four', 'buyer.4'],
    ];

    public function run(): void
    {
        if (app()->environment('production')) {
            $this->command?->error(
                'PopularLivestockDemoSeeder refuses to run in production.',
            );

            return;
        }

        $seller = $this->ensureUser(
            self::EMAIL_PREFIX.'seller@'.self::DEMO_DOMAIN,
            'Popular Demo Ranch',
            SellerCapability::Seller,
        );

        $buyers = array_map(
            fn (array $buyer): User => $this->ensureUser(
                self::EMAIL_PREFIX.$buyer[1].'@'.self::DEMO_DOMAIN,
                $buyer[0],
                SellerCapability::Buyer,
            ),
            self::BUYERS,
        );

        $createdListings = 0;
        $createdTransactions = 0;
        $refreshedTransactions = 0;

        foreach (self::TARGETS as $type => $target) {
            for ($index = 1; $index <= $target; $index++) {
                $listing = Listing::query()->firstOrCreate(
                    [
                        'seller_id' => $seller->id,
                        'livestock_type' => strtolower($type),
                        'breed' => "PopularDemo {$type} #{$index}",
                    ],
                    [
                        'age_value' => 1 + ($index % 3),
                        'age_unit' => 'year',
                        'gender' => $index % 2 === 0 ? 'female' : 'male',
                        'weight_value' => 150 + ($index * 7) % 400,
                        'weight_unit' => 'kg',
                        'quantity' => 1 + ($index % 5),
                        'asking_price' => 15000.00 + (($index * 137) % 70000),
                        'location' => 'Trinidad, Bohol',
                        'health_status' => 'healthy',
                        'vaccination' => 'up_to_date',
                        'short_description' => self::LISTING_MARKER
                            ." Demo {$type} listing {$index} for the Popular Livestock ranking.",
                        'additional_notes' => null,
                        'photos' => [],
                        'status' => ListingStatus::Active,
                    ],
                );

                if ($listing->wasRecentlyCreated) {
                    $createdListings++;
                }

                $buyer = $buyers[$index % count($buyers)];
                $completedAt = $this->completedAt($index);

                $transaction = Transaction::query()->firstOrCreate(
                    [
                        'buyer_id' => $buyer->id,
                        'seller_id' => $seller->id,
                        'listing_id' => $listing->id,
                        'quantity' => 1,
                    ],
                    [
                        'total_amount' => (float) $listing->asking_price,
                        'status' => TransactionStatus::Completed,
                    ],
                );

                if ($transaction->wasRecentlyCreated) {
                    $createdTransactions++;
                } else {
                    $refreshedTransactions++;
                    // Keep only this seeder's own rows inside the live window.
                    $transaction->forceFill([
                        'status' => TransactionStatus::Completed,
                        'total_amount' => (float) $listing->asking_price,
                    ]);
                }

                $transaction->forceFill([
                    'created_at' => $completedAt,
                    'updated_at' => $completedAt,
                ])->save();
            }
        }

        $summary = [];
        foreach (array_keys(self::TARGETS) as $type) {
            $summary[] = $type.': '.Transaction::query()
                ->join('listings', 'listings.id', '=', 'transactions.listing_id')
                ->where('transactions.status', TransactionStatus::Completed)
                ->whereRaw('LOWER(listings.livestock_type) = ?', [strtolower($type)])
                ->where('listings.seller_id', $seller->id)
                ->distinct()
                ->count('transactions.id');
        }

        $this->command?->info(
            'PopularLivestockDemoSeeder: '
            ."{$createdListings} listing(s) created, "
            ."{$createdTransactions} transaction(s) created, "
            ."{$refreshedTransactions} demo transaction(s) refreshed. "
            .'Completed demo sales — '.implode(', ', $summary).'.',
        );
    }

    private function ensureUser(string $email, string $name, SellerCapability $capability): User
    {
        $user = User::query()->where('email', $email)->first();

        if ($user !== null) {
            return $user;
        }

        $user = new User;
        $user->forceFill([
            'name' => $name,
            'email' => $email,
            'password' => Str::random(40),
            'role' => UserRole::User,
            'seller_capability' => $capability,
            'email_verified_at' => now(),
        ])->save();

        return $user;
    }

    /**
     * A completion timestamp inside the 30-day window, spread deterministically
     * so the ranking has real date variety without randomness.
     */
    private function completedAt(int $index): Carbon
    {
        return now()
            ->subDays(($index * 3) % 28 + 1)
            ->setTime(8 + ($index % 10), ($index * 7) % 60);
    }
}
