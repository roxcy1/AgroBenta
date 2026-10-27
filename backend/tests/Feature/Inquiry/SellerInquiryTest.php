<?php

namespace Tests\Feature\Inquiry;

use App\Enums\InquiryStatus;
use App\Enums\ListingStatus;
use App\Enums\UserRole;
use App\Models\Inquiry;
use App\Models\Listing;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Seller received-inquiry list - `GET /api/seller/inquiries`.
 *
 * The read counterpart of `MobileInquiryTest`. The rules under test are the
 * ones the functional documentation states (section 8.2): a seller sees only the
 * inquiries received against their own listings, the scope comes from the
 * token, and the mobile projection carries no buyer contact details and no
 * administrator-facing status.
 */
class SellerInquiryTest extends TestCase
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

    // ---------------------------------------------------------------- access

    #[Test]
    public function a_guest_cannot_read_received_inquiries(): void
    {
        $this->getJson('/api/seller/inquiries')->assertUnauthorized();
    }

    #[Test]
    public function a_buyer_cannot_read_received_inquiries(): void
    {
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->buyer))
            ->getJson('/api/seller/inquiries')
            ->assertForbidden();
    }

    #[Test]
    public function an_admin_token_cannot_reach_the_seller_api(): void
    {
        $admin = User::factory()->admin()->create();
        $token = $admin->createToken('admin', ['admin'])->plainTextToken;

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->getJson('/api/seller/inquiries')
            ->assertForbidden();
    }

    // ---------------------------------------------------------------- scope

    #[Test]
    public function a_seller_sees_only_inquiries_for_their_own_listings(): void
    {
        $own = $this->createInquiry($this->seller);
        $other = $this->createInquiry($this->otherSeller);

        $data = $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->getJson('/api/seller/inquiries')
            ->assertOk()
            ->json('data');

        $this->assertCount(1, $data['inquiries']);
        $this->assertSame($own->id, $data['inquiries'][0]['id']);
        $this->assertNotSame($other->id, $data['inquiries'][0]['id']);
        $this->assertSame(1, $data['pagination']['total']);
    }

    #[Test]
    public function an_empty_inbox_returns_an_empty_page(): void
    {
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->getJson('/api/seller/inquiries')
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.inquiries', [])
            ->assertJsonPath('data.pagination', [
                'current_page' => 1,
                'last_page' => 1,
                'per_page' => 15,
                'total' => 0,
            ]);
    }

    #[Test]
    public function the_list_is_newest_first_and_paginated(): void
    {
        $oldest = $this->createInquiry($this->seller);
        $middle = $this->createInquiry($this->seller);
        $newest = $this->createInquiry($this->seller);

        $firstPage = $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->getJson('/api/seller/inquiries?per_page=2')
            ->assertOk()
            ->json('data');

        $this->assertSame([$newest->id, $middle->id], array_column($firstPage['inquiries'], 'id'));
        $this->assertSame(1, $firstPage['pagination']['current_page']);
        $this->assertSame(2, $firstPage['pagination']['last_page']);
        $this->assertSame(2, $firstPage['pagination']['per_page']);
        $this->assertSame(3, $firstPage['pagination']['total']);

        $secondPage = $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->getJson('/api/seller/inquiries?per_page=2&page=2')
            ->assertOk()
            ->json('data');

        $this->assertSame([$oldest->id], array_column($secondPage['inquiries'], 'id'));
        $this->assertSame(2, $secondPage['pagination']['current_page']);
    }

    // ------------------------------------------------------------ projection

    #[Test]
    public function the_projection_names_the_buyer_and_listing_without_private_details(): void
    {
        $listing = $this->createListing($this->seller, [
            'livestock_type' => 'goat',
            'breed' => 'Boer',
        ]);

        $inquiry = $this->createInquiry($this->seller, [
            'listing' => $listing,
            'subject' => 'Bulk purchase',
            'message' => 'Can I buy three?',
            'purchase_interest' => true,
            'transaction_method' => 'arrange_delivery',
            'delivery_method' => 'arrange_delivery',
            'delivery_fee' => '1500.50',
            'contact_method' => 'in_app_message',
            'preferred_schedule' => '2026-11-01',
        ]);

        $data = $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->getJson('/api/seller/inquiries')
            ->assertOk()
            ->json('data.inquiries.0');

        $this->assertSame($inquiry->id, $data['id']);
        $this->assertSame(['id' => $this->buyer->id, 'name' => 'Pedro Reyes'], $data['buyer']);
        $this->assertSame([
            'id' => $listing->id,
            'livestock_type' => 'goat',
            'breed' => 'Boer',
        ], $data['listing']);
        $this->assertSame('Bulk purchase', $data['subject']);
        $this->assertSame('Can I buy three?', $data['message']);
        $this->assertTrue($data['purchase_interest']);
        $this->assertSame('arrange_delivery', $data['transaction_method']);
        $this->assertSame('arrange_delivery', $data['delivery_method']);
        $this->assertSame('1500.50', $data['delivery_fee']);
        $this->assertSame('in_app_message', $data['contact_method']);
        $this->assertSame('2026-11-01', $data['preferred_schedule']);
        $this->assertArrayHasKey('created_at', $data);

        $this->assertArrayNotHasKey('email', $data['buyer']);
        $this->assertArrayNotHasKey('status', $data);
        $this->assertArrayNotHasKey('seller', $data);
        $this->assertArrayNotHasKey('seller_id', $data);
    }

    #[Test]
    public function an_inquiry_whose_listing_was_deleted_still_appears(): void
    {
        $listing = $this->createListing($this->seller);
        $inquiry = $this->createInquiry($this->seller, ['listing' => $listing]);

        $listing->delete();

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->getJson('/api/seller/inquiries')
            ->assertOk()
            ->assertJsonPath('data.inquiries.0.id', $inquiry->id)
            ->assertJsonPath('data.inquiries.0.listing', null);
    }

    // ------------------------------------------------------------ parameters

    /**
     * @return array<string, array{string}>
     */
    public static function prohibitedQueryParameters(): array
    {
        return [
            'buyer_id' => ['buyer_id'],
            'seller_id' => ['seller_id'],
            'status' => ['status'],
        ];
    }

    #[Test]
    #[DataProvider('prohibitedQueryParameters')]
    public function server_owned_fields_are_refused_as_query_parameters(string $field): void
    {
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->getJson('/api/seller/inquiries?'.$field.'=1')
            ->assertStatus(422)
            ->assertJsonValidationErrors($field);
    }

    #[Test]
    public function pagination_parameters_are_bounded(): void
    {
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->getJson('/api/seller/inquiries?per_page=51')
            ->assertStatus(422)
            ->assertJsonValidationErrors('per_page');

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->getJson('/api/seller/inquiries?page=0')
            ->assertStatus(422)
            ->assertJsonValidationErrors('page');
    }
}
