<?php

namespace Tests\Feature\SellerDashboard;

use App\Enums\InquiryStatus;
use App\Enums\ListingStatus;
use App\Enums\TransactionStatus;
use App\Enums\UserRole;
use App\Models\Inquiry;
use App\Models\Listing;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Seller dashboard - `GET /api/seller/dashboard`.
 *
 * The summary must come only from the token seller's own records. Completed,
 * cancelled, revenue, and conversion figures are deliberately absent.
 */
class SellerDashboardTest extends TestCase
{
    use RefreshDatabase;

    private User $seller;

    private User $otherSeller;

    private User $buyer;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seller = User::factory()->seller()->create([
            'role' => UserRole::User,
            'name' => 'Juan Dela Cruz',
            'email' => 'juan@agrobenta.test',
        ]);

        $this->otherSeller = User::factory()->seller()->create([
            'role' => UserRole::User,
            'name' => 'Maria Santos',
            'email' => 'maria@agrobenta.test',
        ]);

        $this->buyer = User::factory()->create([
            'role' => UserRole::User,
            'name' => 'Pedro Reyes',
            'email' => 'pedro@agrobenta.test',
        ]);
    }

    private function mobileToken(User $user): string
    {
        return $user->createToken('mobile', ['mobile'])->plainTextToken;
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
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
            'quantity' => 1,
            'asking_price' => 50000.00,
            'location' => 'Trinidad',
            'health_status' => 'healthy',
            'vaccination' => 'up_to_date',
            'short_description' => 'Healthy Angus bull',
            'additional_notes' => null,
            'photos' => [],
            'status' => ListingStatus::Active,
        ], $overrides));
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function createInquiry(User $seller, array $overrides = []): Inquiry
    {
        $listing = $overrides['listing'] ?? $this->createListing($seller);

        unset($overrides['listing']);

        return Inquiry::create(array_merge([
            'buyer_id' => $this->buyer->id,
            'seller_id' => $seller->id,
            'listing_id' => $listing?->id,
            'subject' => 'General Inquiry',
            'message' => 'Is this one still available?',
            'purchase_interest' => null,
            'transaction_method' => null,
            'delivery_method' => null,
            'delivery_fee' => null,
            'contact_method' => null,
            'preferred_schedule' => null,
            'status' => InquiryStatus::Open,
        ], $overrides));
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function createTransaction(Listing $listing, User $buyer, array $overrides = []): Transaction
    {
        return Transaction::create(array_merge([
            'buyer_id' => $buyer->id,
            'seller_id' => $listing->seller_id,
            'listing_id' => $listing->id,
            'quantity' => 1,
            'total_amount' => 50000.00,
            'status' => TransactionStatus::Pending,
        ], $overrides));
    }

    #[Test]
    public function a_guest_cannot_read_the_dashboard(): void
    {
        $this->getJson('/api/seller/dashboard')->assertUnauthorized();
    }

    #[Test]
    public function a_buyer_cannot_read_the_dashboard(): void
    {
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->buyer))
            ->getJson('/api/seller/dashboard')
            ->assertForbidden();
    }

    #[Test]
    public function an_admin_token_cannot_reach_the_seller_dashboard(): void
    {
        $admin = User::factory()->admin()->create();
        $token = $admin->createToken('admin', ['admin'])->plainTextToken;

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->getJson('/api/seller/dashboard')
            ->assertForbidden();
    }

    #[Test]
    public function the_dashboard_counts_only_the_token_sellers_records(): void
    {
        $this->createListing($this->seller, ['status' => ListingStatus::Inactive]);
        $ownSold = $this->createListing($this->seller, ['status' => ListingStatus::Sold]);
        $ownActive = $this->createListing($this->seller, ['status' => ListingStatus::Active]);
        $this->createListing($this->seller, ['status' => ListingStatus::Active]);
        $this->createListing($this->seller, ['status' => ListingStatus::Pending]);
        $this->createListing($this->seller, ['status' => ListingStatus::Draft]);

        $foreignListing = $this->createListing($this->otherSeller, ['status' => ListingStatus::Active]);
        $this->createListing($this->otherSeller, ['status' => ListingStatus::Sold]);

        // One inquiry per buyer per listing is a database rule, so several
        // inquiries against one listing come from different buyers.
        $this->createInquiry($this->seller, ['listing' => $ownActive]);
        $this->createInquiry($this->seller, [
            'listing' => $ownActive,
            'buyer_id' => User::factory()->create()->id,
        ]);
        $this->createInquiry($this->seller, [
            'listing' => $ownActive,
            'buyer_id' => User::factory()->create()->id,
        ]);
        $this->createInquiry($this->otherSeller, ['listing' => $foreignListing]);
        $this->createInquiry($this->otherSeller, [
            'listing' => $foreignListing,
            'buyer_id' => User::factory()->create()->id,
        ]);

        $this->createTransaction($ownActive, $this->buyer);
        $this->createTransaction($ownActive, $this->buyer);
        $this->createTransaction($ownActive, $this->buyer, [
            'status' => TransactionStatus::Completed,
        ]);
        $this->createTransaction($ownSold, $this->buyer, [
            'status' => TransactionStatus::Cancelled,
        ]);

        // The seller is the buyer here, so this must not count as a sale.
        $this->createTransaction($foreignListing, $this->seller);
        // Another seller's sale must not leak into this summary.
        $this->createTransaction($foreignListing, $this->buyer, [
            'status' => TransactionStatus::Completed,
        ]);

        $response = $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->getJson('/api/seller/dashboard')
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.listings', [
                'total' => 6,
                'draft' => 1,
                'pending' => 1,
                'active' => 2,
                'sold' => 1,
                'inactive' => 1,
            ])
            ->assertJsonPath('data.inquiries', ['total' => 3])
            ->assertJsonPath('data.transactions', ['total' => 4, 'pending' => 2]);

        $response->assertJsonMissingPath('data.transactions.completed')
            ->assertJsonMissingPath('data.transactions.cancelled');
    }

    #[Test]
    public function an_empty_dashboard_returns_zeroes_for_every_status(): void
    {
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->getJson('/api/seller/dashboard')
            ->assertOk()
            ->assertJsonPath('data.listings', [
                'total' => 0,
                'draft' => 0,
                'pending' => 0,
                'active' => 0,
                'sold' => 0,
                'inactive' => 0,
            ])
            ->assertJsonPath('data.inquiries', ['total' => 0])
            ->assertJsonPath('data.transactions', ['total' => 0, 'pending' => 0]);
    }

    #[Test]
    public function ownership_cannot_be_selected_with_a_query_parameter(): void
    {
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->getJson('/api/seller/dashboard?seller_id='.$this->otherSeller->id)
            ->assertUnprocessable()
            ->assertJsonValidationErrors('seller_id');
    }
}
