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
 * Seeds realistic, development-only transaction data.
 *
 * The seeder is idempotent. Demo users and listings are matched by their
 * reserved `@agrobenta.test` addresses and catalogue identity, and transactions
 * are matched by their business key, so running it repeatedly never creates
 * duplicates and never modifies records it did not create itself.
 *
 * It is intentionally not registered in DatabaseSeeder so a blanket `db:seed`
 * can never write demo data to a production database. Run it explicitly:
 *
 *     php artisan db:seed --class=TransactionSeeder
 */
class TransactionSeeder extends Seeder
{
    /**
     * Reserved domain for demo accounts, keeping them easy to recognise and
     * impossible to collide with a real user's email address.
     */
    private const DEMO_DOMAIN = 'agrobenta.test';

    /**
     * Demo buyers, as [display name, email local part].
     *
     * @var list<array{0: string, 1: string}>
     */
    private const BUYERS = [
        ['Ana Reyes', 'ana.reyes'],
        ['Mark Villanueva', 'mark.villanueva'],
        ['Grace Lim', 'grace.lim'],
        ['Paolo Cruz', 'paolo.cruz'],
    ];

    /**
     * Demo sellers, as [display name, email local part].
     *
     * @var list<array{0: string, 1: string}>
     */
    private const SELLERS = [
        ['Liza Mercado', 'liza.mercado'],
        ['Bacolod Livestock Trading', 'bacolod.livestock'],
        ['North Ridge Ranch', 'northridge.ranch'],
    ];

    /**
     * Listing catalogue keyed by the seller's position in SELLERS. Each entry is
     * [livestock type, breed, stock, asking price, location].
     *
     * @var array<int, list<array{0: string, 1: string, 2: int, 3: float, 4: string}>>
     */
    private const CATALOGUE = [
        0 => [
            ['cattle', 'Brahman', 5, 48000.00, 'Bukidnon'],
            ['goat', 'Boer', 12, 8500.00, 'Bukidnon'],
        ],
        1 => [
            ['swine', 'Landrace', 20, 12000.00, 'Negros Occidental'],
            ['cattle', 'Holstein', 3, 62000.00, 'Negros Occidental'],
            ['chicken', 'Broiler', 200, 180.00, 'Negros Occidental'],
        ],
        2 => [
            ['cattle', 'Angus', 4, 55000.00, 'Lanao del Norte'],
            ['goat', 'Kalahari', 15, 9000.00, 'Lanao del Norte'],
            ['carabao', 'Philippine Carabao', 2, 75000.00, 'Lanao del Norte'],
        ],
    ];

    /**
     * Number of sales seeded against each listing.
     */
    private const SALES_PER_LISTING = 4;

    public function run(): void
    {
        $buyers = $this->seedBuyers();
        $sellers = $this->seedSellers();
        $listings = $this->seedListings($sellers);

        $created = $this->seedTransactions($buyers, $listings);
        $total = Transaction::query()->count();

        $this->command?->info(
            "TransactionSeeder: {$created} demo transaction(s) created, {$total} total in the database.",
        );
    }

    /**
     * @return list<User>
     */
    private function seedBuyers(): array
    {
        return array_map(
            fn (array $buyer): User => $this->ensureUser(
                $buyer[1].'@'.self::DEMO_DOMAIN,
                $buyer[0],
                UserRole::User,
                SellerCapability::Buyer,
            ),
            self::BUYERS,
        );
    }

    /**
     * @return list<User>
     */
    private function seedSellers(): array
    {
        return array_map(
            fn (array $seller): User => $this->ensureUser(
                $seller[1].'@'.self::DEMO_DOMAIN,
                $seller[0],
                UserRole::User,
                SellerCapability::Seller,
            ),
            self::SELLERS,
        );
    }

    /**
     * Reuses a demo account when it already exists, otherwise creates it.
     *
     * The authority columns are not mass assignable, so this trusted server-side
     * path sets them explicitly. The password is random: these accounts are
     * transaction counterparties, not logins.
     */
    private function ensureUser(string $email, string $name, UserRole $role, SellerCapability $capability): User
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
            'role' => $role,
            'seller_capability' => $capability,
            'email_verified_at' => now(),
        ])->save();

        return $user;
    }

    /**
     * @param  list<User>  $sellers
     * @return list<Listing>
     */
    private function seedListings(array $sellers): array
    {
        $listings = [];

        foreach (self::CATALOGUE as $sellerIndex => $catalogue) {
            $seller = $sellers[$sellerIndex];

            foreach ($catalogue as $index => [$type, $breed, $stock, $price, $location]) {
                $listings[] = Listing::firstOrCreate(
                    [
                        'seller_id' => $seller->id,
                        'livestock_type' => $type,
                        'breed' => $breed,
                    ],
                    [
                        'age_value' => 1 + ($index % 3),
                        'age_unit' => 'year',
                        'gender' => $index % 2 === 0 ? 'male' : 'female',
                        'weight_value' => 120 + ($index * 85),
                        'weight_unit' => 'kg',
                        'quantity' => $stock,
                        'asking_price' => $price,
                        'location' => $location,
                        'health_status' => 'healthy',
                        'vaccination' => 'up_to_date',
                        'short_description' => "{$breed} {$type} available from {$seller->name}.",
                        'photos' => [],
                        'status' => ListingStatus::Active,
                    ],
                );
            }
        }

        return $listings;
    }

    /**
     * Seeds sales across the three transaction statuses and a spread of dates.
     *
     * @param  list<User>  $buyers
     * @param  list<Listing>  $listings
     * @return int the number of transactions created by this run
     */
    private function seedTransactions(array $buyers, array $listings): int
    {
        $statuses = [
            TransactionStatus::Completed,
            TransactionStatus::Pending,
            TransactionStatus::Cancelled,
        ];

        $created = 0;

        foreach ($listings as $listingIndex => $listing) {
            // Each listing receives four sales. Because quantity is unique per
            // listing, the (listing, quantity) pair is a stable natural key for
            // idempotency even without a dedicated column.
            for ($sale = 0; $sale < self::SALES_PER_LISTING; $sale++) {
                $buyer = $buyers[($listingIndex + $sale) % count($buyers)];
                $status = $statuses[($listingIndex + $sale) % count($statuses)];
                $quantity = $sale + 1;
                $amount = round($quantity * (float) $listing->asking_price, 2);
                $createdAt = now()
                    ->subDays(($listingIndex * 5) + ($sale * 3) + 1)
                    ->setTime(8 + ($sale * 2), ($listingIndex * 7 + $sale * 13) % 60);

                if ($this->seedTransaction($listing, $buyer, $quantity, $amount, $status, $createdAt)) {
                    $created++;
                }
            }
        }

        return $created;
    }

    private function seedTransaction(
        Listing $listing,
        User $buyer,
        int $quantity,
        float $amount,
        TransactionStatus $status,
        Carbon $createdAt,
    ): bool {
        $transaction = Transaction::firstOrCreate([
            'buyer_id' => $buyer->id,
            'seller_id' => $listing->seller_id,
            'listing_id' => $listing->id,
            'quantity' => $quantity,
            'total_amount' => $amount,
            'status' => $status->value,
        ]);

        if (! $transaction->wasRecentlyCreated) {
            return false;
        }

        $transaction->forceFill([
            'created_at' => $createdAt,
            'updated_at' => $createdAt,
        ])->save();

        return true;
    }
}
