<?php

namespace Tests\Feature\Admin;

use App\Enums\InquiryContactMethod;
use App\Enums\InquiryStatus;
use App\Enums\InquiryTransactionMethod;
use App\Enums\ListingStatus;
use App\Enums\SellerCapability;
use App\Enums\UserRole;
use App\Models\Inquiry;
use App\Models\Listing;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class InquiryTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    private User $buyer;

    private User $seller;

    protected function setUp(): void
    {
        parent::setUp();

        $this->admin = User::factory()->create([
            'role' => UserRole::Admin,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $this->buyer = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $this->seller = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Seller,
        ]);
    }

    private function adminToken(): string
    {
        return $this->admin->createToken('admin_token', ['admin'])->plainTextToken;
    }

    private function createListing(): Listing
    {
        return Listing::create([
            'seller_id' => $this->seller->id,
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

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function createInquiry(array $overrides = []): Inquiry
    {
        $listing = $overrides['listing_id'] ?? $this->createListing()->id;
        unset($overrides['listing_id']);

        // forceCreate: the helper sets `created_at` to exercise ordering, and
        // that column is deliberately not mass-assignable.
        return Inquiry::forceCreate(array_merge([
            'buyer_id' => $this->buyer->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing,
            'subject' => 'General Inquiry',
            'message' => 'Is this still available?',
            'purchase_interest' => true,
            'transaction_method' => InquiryTransactionMethod::DirectDeal,
            'delivery_method' => 'Pickup',
            'delivery_fee' => 250.00,
            'contact_method' => InquiryContactMethod::InAppMessage,
            'preferred_schedule' => '2026-11-01',
            'status' => InquiryStatus::Open,
        ], $overrides));
    }

    public function test_guest_cannot_access_inquiries(): void
    {
        $response = $this->getJson('/api/admin/inquiries');

        $response->assertStatus(401);
    }

    public function test_regular_user_cannot_access_inquiries(): void
    {
        $token = $this->buyer->createToken('user_token', ['mobile'])->plainTextToken;

        $response = $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/admin/inquiries');

        $response->assertStatus(403);
    }

    public function test_mobile_ability_token_is_refused(): void
    {
        $token = $this->admin->createToken('mobile_token', ['mobile'])->plainTextToken;

        $response = $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/admin/inquiries');

        $response->assertStatus(403);
    }

    public function test_admin_can_list_inquiries(): void
    {
        $this->createInquiry();

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/inquiries');

        $response->assertStatus(200);
        $response->assertJsonStructure([
            'success',
            'data' => [
                'inquiries' => [
                    '*' => [
                        'id',
                        'buyer' => ['id', 'name', 'email'],
                        'seller' => ['id', 'name', 'email'],
                        'listing',
                        'subject',
                        'message',
                        'purchase_interest',
                        'transaction_method',
                        'delivery_method',
                        'delivery_fee',
                        'contact_method',
                        'preferred_schedule',
                        'status',
                        'created_at',
                        'updated_at',
                    ],
                ],
                'pagination' => ['current_page', 'last_page', 'per_page', 'total'],
            ],
        ]);
    }

    public function test_inquiries_are_returned(): void
    {
        $this->createInquiry();
        $this->createInquiry(['status' => InquiryStatus::Closed]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/inquiries');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(2, $data['pagination']['total']);
        $this->assertCount(2, $data['inquiries']);
    }

    public function test_search_works(): void
    {
        $this->createInquiry();

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/inquiries?search='.urlencode($this->buyer->name));

        $response->assertStatus(200);
        $this->assertEquals(1, $response->json('data.pagination.total'));
    }

    public function test_search_matches_message_content(): void
    {
        $this->createInquiry(['message' => 'Do you deliver to Cebu?']);
        $this->createInquiry(['message' => 'Untouched']);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/inquiries?search=available');

        // Only the default-message inquiry matches "available".
        $response->assertStatus(200);
        $this->assertEquals(0, $response->json('data.pagination.total'));

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/inquiries?search=deliver');

        $response->assertStatus(200);
        $this->assertEquals(1, $response->json('data.pagination.total'));
    }

    public function test_status_filter_works(): void
    {
        $this->createInquiry(['status' => InquiryStatus::Open]);
        $this->createInquiry(['status' => InquiryStatus::Closed]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/inquiries?status=closed');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(1, $data['pagination']['total']);
        $this->assertEquals('closed', $data['inquiries'][0]['status']);
    }

    public function test_invalid_status_filter_returns_error(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/inquiries?status=invalid');

        $response->assertStatus(422);
    }

    public function test_pagination_works(): void
    {
        for ($i = 0; $i < 25; $i++) {
            $this->createInquiry();
        }

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/inquiries?per_page=10&page=1');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertCount(10, $data['inquiries']);
        $this->assertEquals(1, $data['pagination']['current_page']);
        $this->assertEquals(3, $data['pagination']['last_page']);
        $this->assertEquals(25, $data['pagination']['total']);
    }

    public function test_results_are_ordered_by_created_at_desc(): void
    {
        $first = $this->createInquiry(['created_at' => now()->subDays(10)]);
        $second = $this->createInquiry(['created_at' => now()->subDays(5)]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/inquiries');

        $response->assertStatus(200);

        $ids = array_column($response->json('data.inquiries'), 'id');

        $this->assertSame([$second->id, $first->id], $ids);
    }

    public function test_admin_can_show_a_single_inquiry(): void
    {
        $inquiry = $this->createInquiry();

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson("/api/admin/inquiries/{$inquiry->id}");

        $response->assertStatus(200);
        $response->assertJsonPath('success', true);
        $response->assertJsonPath('data.id', $inquiry->id);
        $response->assertJsonPath('data.status', 'open');
        $response->assertJsonPath('data.transaction_method', 'direct_deal');
        $response->assertJsonPath('data.contact_method', 'in_app_message');
        $response->assertJsonStructure([
            'data' => [
                'id',
                'buyer' => ['id', 'name', 'email'],
                'seller' => ['id', 'name', 'email'],
                'listing' => ['id', 'livestock_type', 'breed'],
                'subject',
                'message',
                'purchase_interest',
                'transaction_method',
                'delivery_method',
                'delivery_fee',
                'contact_method',
                'preferred_schedule',
                'status',
            ],
        ]);
    }

    public function test_show_returns_not_found_for_missing_inquiry(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/inquiries/999999');

        $response->assertStatus(404);
    }

    public function test_response_does_not_leak_internal_ids(): void
    {
        $this->createInquiry();

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/inquiries');

        $response->assertStatus(200);

        $inquiries = $response->json('data.inquiries');
        $this->assertNotEmpty($inquiries);

        foreach ($inquiries as $inquiry) {
            $this->assertArrayNotHasKey('buyer_id', $inquiry);
            $this->assertArrayNotHasKey('seller_id', $inquiry);
            $this->assertArrayNotHasKey('listing_id', $inquiry);
        }
    }

    public function test_inquiry_survives_a_deleted_listing(): void
    {
        $listing = $this->createListing();
        $inquiry = $this->createInquiry(['listing_id' => $listing->id]);

        $listing->delete();

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson("/api/admin/inquiries/{$inquiry->id}");

        $response->assertStatus(200);
        $response->assertJsonPath('data.listing', null);
        $this->assertDatabaseHas('inquiries', ['id' => $inquiry->id]);
    }

    public function test_admin_can_update_inquiry_status(): void
    {
        $inquiry = $this->createInquiry();

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->patchJson("/api/admin/inquiries/{$inquiry->id}/status", ['status' => 'responded']);

        $response->assertStatus(200);
        $response->assertJsonPath('success', true);
        $response->assertJsonPath('data.status', 'responded');
        $this->assertDatabaseHas('inquiries', ['id' => $inquiry->id, 'status' => 'responded']);
    }

    public function test_update_status_rejects_invalid_value(): void
    {
        $inquiry = $this->createInquiry();

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->patchJson("/api/admin/inquiries/{$inquiry->id}/status", ['status' => 'invalid']);

        $response->assertStatus(422);
        $response->assertJsonValidationErrors(['status']);
        $this->assertDatabaseHas('inquiries', ['id' => $inquiry->id, 'status' => 'open']);
    }

    public function test_update_status_requires_a_status(): void
    {
        $inquiry = $this->createInquiry();

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->patchJson("/api/admin/inquiries/{$inquiry->id}/status", []);

        $response->assertStatus(422);
        $response->assertJsonValidationErrors(['status']);
    }

    public function test_update_status_is_audited(): void
    {
        $inquiry = $this->createInquiry();

        $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->patchJson("/api/admin/inquiries/{$inquiry->id}/status", ['status' => 'closed']);

        $this->assertDatabaseHas('activities', [
            'user_id' => $this->admin->id,
            'action' => 'inquiry_status_updated',
        ]);
    }

    public function test_admin_can_delete_an_inquiry(): void
    {
        $inquiry = $this->createInquiry();

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->deleteJson("/api/admin/inquiries/{$inquiry->id}");

        $response->assertStatus(200);
        $response->assertJsonPath('success', true);
        $this->assertDatabaseMissing('inquiries', ['id' => $inquiry->id]);
    }

    public function test_delete_is_audited(): void
    {
        $inquiry = $this->createInquiry();

        $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->deleteJson("/api/admin/inquiries/{$inquiry->id}");

        $this->assertDatabaseHas('activities', [
            'user_id' => $this->admin->id,
            'action' => 'inquiry_deleted',
        ]);
    }

    public function test_delete_missing_inquiry_returns_not_found(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->deleteJson('/api/admin/inquiries/999999');

        $response->assertStatus(404);
    }
}
