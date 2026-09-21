<?php

namespace Tests\Feature\Admin;

use App\Enums\SellerCapability;
use App\Enums\SellerVerificationStatus;
use App\Enums\UserRole;
use App\Models\SellerVerification;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class SellerVerificationTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();

        $this->admin = User::factory()->create([
            'role' => UserRole::Admin,
            'seller_capability' => SellerCapability::Buyer,
            'created_at' => now()->subDays(30),
        ]);
    }

    private function adminToken(): string
    {
        return $this->admin->createToken('admin_token', ['admin'])->plainTextToken;
    }

    private function createVerification(array $overrides = []): SellerVerification
    {
        $seller = User::factory()->seller()->create(['role' => UserRole::User]);

        return SellerVerification::create(array_merge([
            'user_id' => $seller->id,
            'business_name' => 'Test Livestock Farm',
            'business_location' => 'Bukidnon',
            'business_description' => 'A test livestock farm',
            'status' => SellerVerificationStatus::Submitted,
            'submitted_at' => now(),
        ], $overrides));
    }

    public function test_guest_cannot_access_verifications(): void
    {
        $response = $this->getJson('/api/admin/seller-verifications');

        $response->assertStatus(401);
    }

    public function test_regular_user_cannot_access_verifications(): void
    {
        $user = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $token = $user->createToken('user_token')->plainTextToken;

        $response = $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/admin/seller-verifications');

        $response->assertStatus(403);
    }

    public function test_admin_can_list_verifications(): void
    {
        $this->createVerification();
        $this->createVerification(['status' => SellerVerificationStatus::Approved]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/seller-verifications');

        $response->assertStatus(200);
        $response->assertJsonStructure([
            'success',
            'data' => [
                'verifications' => [
                    '*' => [
                        'id',
                        'seller',
                        'business_name',
                        'business_location',
                        'business_description',
                        'status',
                        'admin_note',
                        'submitted_at',
                        'reviewed_at',
                        'reviewer',
                        'created_at',
                        'updated_at',
                    ],
                ],
                'pagination' => [
                    'current_page',
                    'last_page',
                    'per_page',
                    'total',
                ],
            ],
        ]);
    }

    public function test_search_by_applicant_name(): void
    {
        $seller1 = User::factory()->seller()->create(['name' => 'Juan Dela Cruz', 'role' => UserRole::User]);
        $seller2 = User::factory()->seller()->create(['name' => 'Maria Santos', 'role' => UserRole::User]);

        SellerVerification::create([
            'user_id' => $seller1->id,
            'business_name' => 'Juan Farm',
            'status' => SellerVerificationStatus::Submitted,
            'submitted_at' => now(),
        ]);

        SellerVerification::create([
            'user_id' => $seller2->id,
            'business_name' => 'Maria Farm',
            'status' => SellerVerificationStatus::Submitted,
            'submitted_at' => now(),
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/seller-verifications?search=Juan');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(1, $data['pagination']['total']);
    }

    public function test_search_by_business_name(): void
    {
        $this->createVerification(['business_name' => 'Green Valley Farm']);
        $this->createVerification(['business_name' => 'Sunrise Ranch']);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/seller-verifications?search=Green Valley');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(1, $data['pagination']['total']);
        $this->assertEquals('Green Valley Farm', $data['verifications'][0]['business_name']);
    }

    public function test_filter_by_status(): void
    {
        $this->createVerification(['status' => SellerVerificationStatus::Submitted]);
        $this->createVerification(['status' => SellerVerificationStatus::Submitted]);
        $this->createVerification(['status' => SellerVerificationStatus::Approved]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/seller-verifications?status=submitted');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(2, $data['pagination']['total']);
    }

    public function test_pagination_works(): void
    {
        for ($i = 0; $i < 25; $i++) {
            $this->createVerification();
        }

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/seller-verifications?per_page=10&page=1');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertCount(10, $data['verifications']);
        $this->assertEquals(1, $data['pagination']['current_page']);
        $this->assertEquals(3, $data['pagination']['last_page']);
        $this->assertEquals(25, $data['pagination']['total']);
    }

    public function test_invalid_status_filter_returns_error(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/seller-verifications?status=invalid');

        $response->assertStatus(422);
    }

    public function test_admin_can_approve_verification(): void
    {
        $verification = $this->createVerification();

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->postJson("/api/admin/seller-verifications/{$verification->id}/approve", [
                'admin_note' => 'Verified successfully.',
            ]);

        $response->assertStatus(200);
        $response->assertJsonPath('success', true);
        $response->assertJsonPath('data.status', 'approved');
        $response->assertJsonPath('data.admin_note', 'Verified successfully.');
    }

    public function test_approval_sets_seller_capability(): void
    {
        $verification = $this->createVerification();
        $sellerId = $verification->user_id;

        $this->assertDatabaseHas('users', [
            'id' => $sellerId,
            'seller_capability' => 'seller',
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->postJson("/api/admin/seller-verifications/{$verification->id}/approve");

        $response->assertStatus(200);

        $this->assertDatabaseHas('users', [
            'id' => $sellerId,
            'seller_capability' => 'seller',
        ]);
    }

    public function test_approval_records_reviewed_by(): void
    {
        $verification = $this->createVerification();

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->postJson("/api/admin/seller-verifications/{$verification->id}/approve");

        $response->assertStatus(200);

        $this->assertDatabaseHas('seller_verifications', [
            'id' => $verification->id,
            'reviewed_by' => $this->admin->id,
        ]);
    }

    public function test_approval_records_reviewed_at(): void
    {
        $verification = $this->createVerification();

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->postJson("/api/admin/seller-verifications/{$verification->id}/approve");

        $response->assertStatus(200);

        $this->assertDatabaseHas('seller_verifications', [
            'id' => $verification->id,
        ]);

        $this->assertNotNull($verification->fresh()->reviewed_at);
    }

    public function test_admin_can_reject_verification(): void
    {
        $verification = $this->createVerification();

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->postJson("/api/admin/seller-verifications/{$verification->id}/reject", [
                'admin_note' => 'Incomplete documentation.',
            ]);

        $response->assertStatus(200);
        $response->assertJsonPath('success', true);
        $response->assertJsonPath('data.status', 'rejected');
        $response->assertJsonPath('data.admin_note', 'Incomplete documentation.');
    }

    public function test_rejection_preserves_buyer_capability(): void
    {
        $seller = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $verification = SellerVerification::create([
            'user_id' => $seller->id,
            'business_name' => 'Test Farm',
            'status' => SellerVerificationStatus::Submitted,
            'submitted_at' => now(),
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->postJson("/api/admin/seller-verifications/{$verification->id}/reject");

        $response->assertStatus(200);

        $this->assertDatabaseHas('users', [
            'id' => $seller->id,
            'seller_capability' => 'buyer',
        ]);
    }

    public function test_rejection_records_reviewed_by(): void
    {
        $verification = $this->createVerification();

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->postJson("/api/admin/seller-verifications/{$verification->id}/reject");

        $response->assertStatus(200);

        $this->assertDatabaseHas('seller_verifications', [
            'id' => $verification->id,
            'reviewed_by' => $this->admin->id,
        ]);
    }

    public function test_rejection_records_reviewed_at(): void
    {
        $verification = $this->createVerification();

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->postJson("/api/admin/seller-verifications/{$verification->id}/reject");

        $response->assertStatus(200);

        $this->assertNotNull($verification->fresh()->reviewed_at);
    }

    public function test_verification_history_is_preserved_after_rejection(): void
    {
        $seller = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $verification = SellerVerification::create([
            'user_id' => $seller->id,
            'business_name' => 'Test Farm',
            'business_location' => 'Bukidnon',
            'business_description' => 'A test farm',
            'status' => SellerVerificationStatus::Submitted,
            'submitted_at' => now()->subDays(5),
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->postJson("/api/admin/seller-verifications/{$verification->id}/reject", [
                'admin_note' => 'Insufficient documentation.',
            ]);

        $response->assertStatus(200);

        $verification->refresh();
        $this->assertEquals(SellerVerificationStatus::Rejected, $verification->status);
        $this->assertEquals('Test Farm', $verification->business_name);
        $this->assertEquals('Bukidnon', $verification->business_location);
        $this->assertEquals('Insufficient documentation.', $verification->admin_note);
        $this->assertNotNull($verification->reviewed_at);
    }

    public function test_approved_verification_shows_in_list(): void
    {
        $this->createVerification(['status' => SellerVerificationStatus::Approved]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/seller-verifications?status=approved');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(1, $data['pagination']['total']);
        $this->assertEquals('approved', $data['verifications'][0]['status']);
    }

    public function test_rejected_verification_shows_in_list(): void
    {
        $this->createVerification(['status' => SellerVerificationStatus::Rejected]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/seller-verifications?status=rejected');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(1, $data['pagination']['total']);
        $this->assertEquals('rejected', $data['verifications'][0]['status']);
    }
}
