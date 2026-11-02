<?php

namespace Tests\Feature\Inquiry;

use App\Enums\ListingStatus;
use App\Enums\OfferStatus;
use App\Enums\UserRole;
use App\Models\Inquiry;
use App\Models\Listing;
use App\Models\Offer;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * `GET /api/inquiries` — the Messages "Inquiries" tab.
 *
 * Only the caller's own active inquiries, on the side the Account Mode asks
 * for, and never one whose offer was already accepted (that is a transaction
 * now and belongs to the Transactions tab).
 */
class MobileInquiryListTest extends TestCase
{
    use RefreshDatabase;

    private User $buyer;

    private User $seller;

    private User $other;

    protected function setUp(): void
    {
        parent::setUp();

        $this->buyer = User::factory()->create([
            'role' => UserRole::User,
            'name' => 'Pedro Reyes',
        ]);
        $this->seller = User::factory()->seller()->create([
            'role' => UserRole::User,
            'name' => 'Juan Dela Cruz',
        ]);
        $this->other = User::factory()->create([
            'role' => UserRole::User,
            'name' => 'Ana Cruz',
        ]);
    }

    private function mobileToken(User $user): string
    {
        return $user->createToken('mobile', ['mobile'])->plainTextToken;
    }

    private function createListing(User $seller): Listing
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
            'quantity' => 5,
            'asking_price' => 50000.00,
            'location' => 'Bukidnon',
            'health_status' => 'healthy',
            'vaccination' => 'up_to_date',
            'short_description' => 'Healthy Angus bull',
            'additional_notes' => null,
            'photos' => [],
            'status' => ListingStatus::Active,
        ]);
    }

    private function createInquiry(Listing $listing, User $buyer, User $seller): Inquiry
    {
        return Inquiry::create([
            'buyer_id' => $buyer->id,
            'seller_id' => $seller->id,
            'listing_id' => $listing->id,
            'subject' => 'Is this still available?',
            'message' => 'I would like to buy this animal.',
            'status' => 'open',
            'payment_method' => 'gcash',
            'collection_method' => 'farm_pickup',
            'preferred_schedule' => now()->addDays(2)->toDateString(),
        ]);
    }

    /**
     * @return array<int, array<string, mixed>>
     */
    private function listFor(User $user, ?string $role = null): array
    {
        $query = $role === null ? '' : '?role='.$role;

        return $this->withHeader(
            'Authorization',
            'Bearer '.$this->mobileToken($user),
        )->getJson('/api/inquiries'.$query)
            ->assertOk()
            ->json('data.inquiries');
    }

    #[Test]
    public function a_buyer_sees_their_active_inquiry_with_the_counterpart_and_listing(): void
    {
        $listing = $this->createListing($this->seller);
        $inquiry = $this->createInquiry($listing, $this->buyer, $this->seller);

        Offer::create([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'seller_id' => $this->seller->id,
            'buyer_id' => $this->buyer->id,
            'proposed_amount' => 48000.00,
            'status' => OfferStatus::Pending,
        ]);

        $items = $this->listFor($this->buyer, 'buyer');

        $this->assertCount(1, $items);
        $this->assertSame($inquiry->id, $items[0]['id']);
        $this->assertSame('buyer', $items[0]['role']);
        $this->assertSame('cattle Angus', $items[0]['listing']['title']);
        $this->assertSame('50000.00', (string) $items[0]['listing']['asking_price']);
        $this->assertSame($this->seller->name, $items[0]['counterpart']['name']);
        $this->assertSame('pending', $items[0]['latest_offer']['status']);
        $this->assertSame('48000.00', $items[0]['latest_offer']['proposed_amount']);
    }

    #[Test]
    public function the_seller_sees_the_same_inquiry_from_their_side(): void
    {
        $listing = $this->createListing($this->seller);
        $this->createInquiry($listing, $this->buyer, $this->seller);

        $items = $this->listFor($this->seller, 'seller');

        $this->assertCount(1, $items);
        $this->assertSame('seller', $items[0]['role']);
        $this->assertSame($this->buyer->name, $items[0]['counterpart']['name']);
    }

    #[Test]
    public function an_accepted_inquiry_is_not_listed(): void
    {
        $listing = $this->createListing($this->seller);
        $inquiry = $this->createInquiry($listing, $this->buyer, $this->seller);

        Offer::create([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'seller_id' => $this->seller->id,
            'buyer_id' => $this->buyer->id,
            'proposed_amount' => 48000.00,
            'status' => OfferStatus::Accepted,
        ]);

        $this->assertCount(0, $this->listFor($this->buyer, 'buyer'));
        $this->assertCount(0, $this->listFor($this->seller, 'seller'));
    }

    #[Test]
    public function another_users_inquiry_is_never_listed(): void
    {
        $listing = $this->createListing($this->seller);
        $this->createInquiry($listing, $this->other, $this->seller);

        $this->assertCount(0, $this->listFor($this->buyer, 'buyer'));
    }

    #[Test]
    public function ownership_filters_are_refused(): void
    {
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->buyer))
            ->getJson('/api/inquiries?buyer_id='.$this->buyer->id)
            ->assertStatus(422)
            ->assertJsonValidationErrors(['buyer_id']);
    }
}
