<?php

namespace Tests\Feature\Marketplace;

use App\Enums\ListingStatus;
use App\Enums\TransactionStatus;
use App\Enums\UserRole;
use App\Models\Listing;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * `GET /api/marketplace/popular-livestock`.
 *
 * Popularity is completed sales only: the count is distinct completed
 * transactions inside the last 30 days, over the canonical categories.
 * Pending, cancelled, older sales and non-canonical livestock types never
 * count.
 */
class PopularLivestockTest extends TestCase
{
    use RefreshDatabase;

    private User $buyer;

    private User $seller;

    protected function setUp(): void
    {
        parent::setUp();

        $this->buyer = User::factory()->create(['role' => UserRole::User]);
        $this->seller = User::factory()->seller()->create(['role' => UserRole::User]);
    }

    private function createListing(string $type): Listing
    {
        return Listing::create([
            'seller_id' => $this->seller->id,
            'livestock_type' => $type,
            'breed' => 'Demo',
            'age_value' => 2,
            'age_unit' => 'year',
            'gender' => 'male',
            'weight_value' => 500,
            'weight_unit' => 'kg',
            'quantity' => 5,
            'asking_price' => 50000.00,
            'location' => 'Bukidnon',
            'health_status' => 'healthy',
            'vaccination' => 'up_to_date',
            'short_description' => 'Demo listing',
            'additional_notes' => null,
            'photos' => [],
            'status' => ListingStatus::Active,
        ]);
    }

    private function completeSale(
        Listing $listing,
        ?\DateTimeInterface $completedAt = null,
        TransactionStatus $status = TransactionStatus::Completed,
    ): Transaction {
        $transaction = Transaction::query()->create([
            'buyer_id' => $this->buyer->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'quantity' => 1,
            'total_amount' => 45000.00,
            'status' => $status,
        ]);

        if ($completedAt !== null) {
            // `updated_at` is the completion timestamp; the query builder is
            // used so Eloquent does not immediately overwrite it with "now".
            DB::table('transactions')
                ->where('id', $transaction->id)
                ->update(['updated_at' => $completedAt]);
        }

        return $transaction;
    }

    /**
     * @return array<int, array<string, mixed>>
     */
    private function categories(): array
    {
        return $this->withHeader(
            'Authorization',
            'Bearer '.$this->buyer->createToken('mobile', ['mobile'])->plainTextToken,
        )->getJson('/api/marketplace/popular-livestock')
            ->assertOk()
            ->json('data.categories');
    }

    #[Test]
    public function it_ranks_the_canonical_categories_by_completed_sales(): void
    {
        $cattle = $this->createListing('cattle');
        $goat = $this->createListing('goat');
        $swine = $this->createListing('swine');
        $chicken = $this->createListing('chicken');

        $this->completeSale($cattle);
        $this->completeSale($cattle);
        $this->completeSale($goat);
        $this->completeSale($swine);
        $this->completeSale($chicken);

        $categories = $this->categories();

        $this->assertSame(['Cattle', 'Chicken', 'Goat', 'Swine'], array_column($categories, 'livestock_type'));
        $this->assertSame([2, 1, 1, 1], array_column($categories, 'completed_sales'));

        $response = $this->withHeader(
            'Authorization',
            'Bearer '.$this->buyer->createToken('mobile', ['mobile'])->plainTextToken,
        )->getJson('/api/marketplace/popular-livestock')->assertOk();

        $this->assertSame(30, $response->json('data.window_days'));
    }

    #[Test]
    public function sales_older_than_thirty_days_do_not_count(): void
    {
        $cattle = $this->createListing('cattle');
        $goat = $this->createListing('goat');

        $this->completeSale($cattle, now()->subDays(31));
        $this->completeSale($goat, now()->subDays(2));

        $categories = $this->categories();

        $this->assertSame(['Goat'], array_column($categories, 'livestock_type'));
        $this->assertSame(1, $categories[0]['completed_sales']);
    }

    #[Test]
    public function pending_cancelled_and_non_canonical_listings_are_excluded(): void
    {
        $cattle = $this->createListing('cattle');
        $this->completeSale($cattle, null, TransactionStatus::Pending);
        $this->completeSale($cattle, null, TransactionStatus::Cancelled);

        $this->completeSale($this->createListing('Cow'));
        $this->completeSale($this->createListing('Poultry'));

        $this->assertSame([], $this->categories());
    }

    #[Test]
    public function every_completed_transaction_is_counted_once(): void
    {
        $cattle = $this->createListing('cattle');

        $this->completeSale($cattle);
        $this->completeSale($cattle);

        $categories = $this->categories();

        $this->assertSame(1, count($categories));
        $this->assertSame(2, $categories[0]['completed_sales']);
    }

    #[Test]
    public function a_window_with_no_completed_sales_returns_an_empty_list(): void
    {
        $this->createListing('cattle');

        $this->assertSame([], $this->categories());
    }

    #[Test]
    public function guests_cannot_read_the_ranking(): void
    {
        $this->getJson('/api/marketplace/popular-livestock')->assertStatus(401);
    }
}
