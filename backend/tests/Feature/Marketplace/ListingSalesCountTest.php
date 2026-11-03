<?php

namespace Tests\Feature\Marketplace;

use App\Enums\ListingStatus;
use App\Enums\TransactionStatus;
use App\Enums\UserRole;
use App\Models\Listing;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * `completed_sales` on the marketplace list and detail payloads.
 *
 * The count belongs to one listing id: a seller's other listings, another
 * seller's listings, pending and cancelled rows never contribute. The list and
 * detail projections must agree because they share the same aggregate.
 */
class ListingSalesCountTest extends TestCase
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

    private function createListing(User $seller, array $overrides = []): Listing
    {
        return Listing::create(array_merge([
            'seller_id' => $seller->id,
            'livestock_type' => 'cattle',
            'breed' => 'Angus',
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
            'short_description' => 'Healthy Angus bull',
            'additional_notes' => null,
            'photos' => [],
            'status' => ListingStatus::Active,
        ], $overrides));
    }

    private function sale(
        Listing $listing,
        TransactionStatus $status = TransactionStatus::Completed,
    ): Transaction {
        return Transaction::query()->create([
            'buyer_id' => $this->buyer->id,
            'seller_id' => $listing->seller_id,
            'listing_id' => $listing->id,
            'quantity' => 1,
            'total_amount' => 45000.00,
            'status' => $status,
        ]);
    }

    /**
     * @return array<int, array<string, mixed>>
     */
    private function listListings(): array
    {
        return $this->withHeader(
            'Authorization',
            'Bearer '.$this->buyer->createToken('mobile', ['mobile'])->plainTextToken,
        )->getJson('/api/listings')
            ->assertOk()
            ->json('data.listings');
    }

    #[Test]
    public function the_list_and_detail_report_the_same_per_listing_completed_count(): void
    {
        $first = $this->createListing($this->seller);
        $second = $this->createListing($this->seller, [
            'livestock_type' => 'goat',
            'breed' => 'Boer',
        ]);

        $this->sale($first);
        $this->sale($first);
        $this->sale($first, TransactionStatus::Pending);
        $this->sale($first, TransactionStatus::Cancelled);
        $this->sale($second);

        $list = collect($this->listListings())->keyBy('id');

        $this->assertSame(2, $list[$first->id]['completed_sales']);
        $this->assertSame(1, $list[$second->id]['completed_sales']);

        $detail = $this->withHeader(
            'Authorization',
            'Bearer '.$this->buyer->createToken('mobile', ['mobile'])->plainTextToken,
        )->getJson('/api/listings/'.$first->id)
            ->assertOk()
            ->json('data');

        $this->assertSame(2, $detail['completed_sales']);
        $this->assertSame($list[$first->id]['completed_sales'], $detail['completed_sales']);
    }

    #[Test]
    public function a_listing_with_no_sales_reports_zero(): void
    {
        $listing = $this->createListing($this->seller);

        $this->assertSame(0, $this->listListings()[0]['completed_sales']);

        $detail = $this->withHeader(
            'Authorization',
            'Bearer '.$this->buyer->createToken('mobile', ['mobile'])->plainTextToken,
        )->getJson('/api/listings/'.$listing->id)
            ->assertOk()
            ->json('data');

        $this->assertSame(0, $detail['completed_sales']);
    }

    #[Test]
    public function another_sellers_sales_are_never_counted(): void
    {
        $other = User::factory()->seller()->create(['role' => UserRole::User]);
        $mine = $this->createListing($this->seller);
        $theirs = $this->createListing($other);

        $this->sale($theirs);
        $this->sale($theirs);

        $list = collect($this->listListings())->keyBy('id');

        $this->assertSame(0, $list[$mine->id]['completed_sales']);
        $this->assertSame(2, $list[$theirs->id]['completed_sales']);
    }
}
