<?php

namespace Tests\Feature\Admin;

use App\Enums\ListingStatus;
use App\Enums\SellerCapability;
use App\Enums\SellerVerificationStatus;
use App\Enums\TransactionStatus;
use App\Enums\UserRole;
use App\Models\Activity;
use App\Models\Listing;
use App\Models\SellerVerification;
use App\Models\Transaction;
use App\Models\User;
use App\Notifications\SellerVerificationRevoked;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Notification;
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
            'phone' => '09171234567',
            'address' => 'Trinidad, Bohol',
            'business_name' => 'Test Livestock Farm',
            'business_location' => 'Bukidnon',
            'business_description' => 'A test livestock farm',
            'status' => SellerVerificationStatus::Submitted,
            'submitted_at' => now(),
        ], $overrides));
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function verificationFor(User $seller, array $overrides = []): SellerVerification
    {
        return SellerVerification::create(array_merge([
            'user_id' => $seller->id,
            'phone' => '09171234567',
            'address' => 'Trinidad, Bohol',
            'business_name' => 'Test Livestock Farm',
            'business_location' => 'Bukidnon',
            'business_description' => 'A test livestock farm',
            'status' => SellerVerificationStatus::Submitted,
            'submitted_at' => now(),
        ], $overrides));
    }

    private function applicant(): User
    {
        return User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);
    }

    private function listingFor(User $seller, ListingStatus $status): Listing
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
            'quantity' => 3,
            'asking_price' => 50000.00,
            'location' => 'Bukidnon',
            'health_status' => 'healthy',
            'vaccination' => 'up_to_date',
            'short_description' => 'Healthy Angus bull',
            'additional_notes' => null,
            'photos' => [],
            'status' => $status,
            'admin_note' => null,
        ]);
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
                        'phone',
                        'address',
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

    public function test_id_document_ref_is_exposed_in_the_admin_resource(): void
    {
        // The admin review UI renders the ID reference as plain text, so the
        // admin resource must carry it — unlike the mobile projection, which
        // already includes it but strips the applicant's identity fields (F-08).
        $withReference = $this->createVerification(['id_document_ref' => 'ID-777888']);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson("/api/admin/seller-verifications/{$withReference->id}");

        $response->assertStatus(200);
        $response->assertJsonPath('data.id_document_ref', 'ID-777888');

        // The field is optional, so it must render as an explicit null rather
        // than being dropped from the payload.
        $withoutReference = $this->createVerification();

        $nullable = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson("/api/admin/seller-verifications/{$withoutReference->id}");

        $nullable->assertStatus(200);
        $nullable->assertJsonPath('data.id_document_ref', null);
    }

    public function test_admin_resource_includes_id_snapshot_and_side_declaration(): void
    {
        $verification = $this->createVerification([
            'government_id_type' => 'others',
            'government_id_description' => 'Barangay ID',
            'has_no_back_image' => true,
        ]);

        $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson("/api/admin/seller-verifications/{$verification->id}")
            ->assertOk()
            ->assertJsonPath('data.government_id_type', 'others')
            ->assertJsonPath('data.government_id_description', 'Barangay ID')
            ->assertJsonPath('data.has_no_back_image', true)
            ->assertJsonPath('data.has_id_document_back', false);
    }

    public function test_phone_and_address_snapshots_are_exposed_to_admin_review(): void
    {
        $verification = $this->createVerification([
            'phone' => '09987654321',
            'address' => 'Poblacion, Trinidad, Bohol',
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson("/api/admin/seller-verifications/{$verification->id}");

        $response->assertOk()
            ->assertJsonPath('data.phone', '09987654321')
            ->assertJsonPath('data.address', 'Poblacion, Trinidad, Bohol');
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

    public function test_admin_can_finish_reviewing_a_preserved_verification_after_account_deactivation(): void
    {
        $verification = $this->createVerification();
        $token = $this->adminToken();

        $this->withHeader('Authorization', "Bearer {$token}")
            ->deleteJson("/api/admin/users/{$verification->user_id}", [
                'reason' => 'Policy violation confirmed.',
            ])
            ->assertOk();

        $this->withHeader('Authorization', "Bearer {$token}")
            ->postJson("/api/admin/seller-verifications/{$verification->id}/approve")
            ->assertOk()
            ->assertJsonPath('data.status', 'approved')
            ->assertJsonPath('data.seller.id', $verification->user_id);

        $this->assertSoftDeleted('users', ['id' => $verification->user_id]);
        $this->assertDatabaseHas('seller_verifications', [
            'id' => $verification->id,
            'status' => SellerVerificationStatus::Approved->value,
        ]);
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
            ->postJson("/api/admin/seller-verifications/{$verification->id}/reject", [
                'admin_note' => 'Incomplete documentation.',
            ]);

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
            ->postJson("/api/admin/seller-verifications/{$verification->id}/reject", [
                'admin_note' => 'Incomplete documentation.',
            ]);

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
            ->postJson("/api/admin/seller-verifications/{$verification->id}/reject", [
                'admin_note' => 'Incomplete documentation.',
            ]);

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

    public function test_rejection_requires_an_admin_note(): void
    {
        $verification = $this->createVerification();

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->postJson("/api/admin/seller-verifications/{$verification->id}/reject");

        $response->assertStatus(422);
        $response->assertJsonValidationErrors('admin_note');

        // Refused, not applied: the record is still awaiting review.
        $this->assertEquals(SellerVerificationStatus::Submitted, $verification->fresh()->status);
    }

    public function test_rejection_revokes_seller_capability(): void
    {
        $seller = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Seller,
        ]);

        // An approved applicant who is re-reviewed and rejected must lose the
        // capability the earlier approval granted (F-09b).
        $this->verificationFor($seller, [
            'status' => SellerVerificationStatus::Approved,
            'submitted_at' => now()->subDays(10),
            'reviewed_at' => now()->subDays(9),
        ]);
        $current = $this->verificationFor($seller, [
            'status' => SellerVerificationStatus::Submitted,
            'submitted_at' => now(),
        ]);

        $this->assertSame(SellerCapability::Seller, $seller->fresh()->seller_capability);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->postJson("/api/admin/seller-verifications/{$current->id}/reject", [
                'admin_note' => 'Rejected on re-review.',
            ]);

        $response->assertStatus(200);

        $this->assertDatabaseHas('users', [
            'id' => $seller->id,
            'seller_capability' => 'buyer',
        ]);
    }

    public function test_stale_record_cannot_be_approved(): void
    {
        $seller = $this->applicant();

        $stale = $this->verificationFor($seller, [
            'status' => SellerVerificationStatus::Submitted,
            'submitted_at' => now()->subDays(5),
        ]);
        $latest = $this->verificationFor($seller, [
            'status' => SellerVerificationStatus::Submitted,
            'submitted_at' => now(),
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->postJson("/api/admin/seller-verifications/{$stale->id}/approve");

        $response->assertStatus(409);

        $this->assertSame(SellerCapability::Buyer, $seller->fresh()->seller_capability);
        $this->assertEquals(SellerVerificationStatus::Submitted, $stale->fresh()->status);
        $this->assertEquals(SellerVerificationStatus::Submitted, $latest->fresh()->status);
    }

    public function test_stale_record_cannot_be_rejected(): void
    {
        $seller = $this->applicant();

        $stale = $this->verificationFor($seller, [
            'status' => SellerVerificationStatus::Submitted,
            'submitted_at' => now()->subDays(5),
        ]);
        $latest = $this->verificationFor($seller, [
            'status' => SellerVerificationStatus::Submitted,
            'submitted_at' => now(),
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->postJson("/api/admin/seller-verifications/{$stale->id}/reject", [
                'admin_note' => 'Intended for the older record.',
            ]);

        $response->assertStatus(409);

        $this->assertEquals(SellerVerificationStatus::Submitted, $stale->fresh()->status);
        $this->assertEquals(SellerVerificationStatus::Submitted, $latest->fresh()->status);
    }

    public function test_stale_approval_cannot_regrant_capability_after_a_newer_rejection(): void
    {
        $seller = $this->applicant();

        $stale = $this->verificationFor($seller, [
            'status' => SellerVerificationStatus::Submitted,
            'submitted_at' => now()->subDays(10),
        ]);
        $this->verificationFor($seller, [
            'status' => SellerVerificationStatus::Rejected,
            'admin_note' => 'Newer rejection stands.',
            'submitted_at' => now(),
            'reviewed_at' => now(),
        ]);

        // Approving the stale record would silently re-grant selling after the
        // newer rejection. It must be refused (F-09).
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->postJson("/api/admin/seller-verifications/{$stale->id}/approve");

        $response->assertStatus(409);

        $this->assertSame(SellerCapability::Buyer, $seller->fresh()->seller_capability);
        $this->assertEquals(SellerVerificationStatus::Submitted, $stale->fresh()->status);
    }

    public function test_already_reviewed_record_cannot_be_reviewed_again(): void
    {
        $verification = $this->createVerification([
            'status' => SellerVerificationStatus::Approved,
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->postJson("/api/admin/seller-verifications/{$verification->id}/approve");

        $response->assertStatus(409);
    }

    public function test_list_shows_only_the_latest_record_per_applicant(): void
    {
        $seller = $this->applicant();

        $this->verificationFor($seller, [
            'status' => SellerVerificationStatus::Submitted,
            'submitted_at' => now()->subDays(5),
        ]);
        $current = $this->verificationFor($seller, [
            'status' => SellerVerificationStatus::Rejected,
            'admin_note' => 'Rejected.',
            'submitted_at' => now(),
            'reviewed_at' => now(),
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/seller-verifications');

        $response->assertStatus(200);
        $this->assertEquals(1, $response->json('data.pagination.total'));
        $this->assertEquals($current->id, $response->json('data.verifications.0.id'));
        $this->assertEquals('rejected', $response->json('data.verifications.0.status'));

        // The stale older record must not surface under its own status filter.
        $filtered = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/seller-verifications?status=submitted');

        $this->assertEquals(0, $filtered->json('data.pagination.total'));
    }

    public function test_pending_filter_lists_submitted_and_pending_review_together(): void
    {
        $this->createVerification(['status' => SellerVerificationStatus::Submitted]);
        $this->createVerification(['status' => SellerVerificationStatus::PendingReview]);
        $this->createVerification(['status' => SellerVerificationStatus::Approved]);
        $this->createVerification(['status' => SellerVerificationStatus::Rejected]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/seller-verifications?status=pending');

        $response->assertOk();
        $this->assertEquals(2, $response->json('data.pagination.total'));
        $statuses = collect($response->json('data.verifications'))->pluck('status')->sort()->values()->all();
        $this->assertEquals(['pending_review', 'submitted'], $statuses);
    }

    public function test_submitted_log_keeps_decided_applications_and_every_resubmission(): void
    {
        $seller = $this->applicant();

        $this->verificationFor($seller, [
            'status' => SellerVerificationStatus::Rejected,
            'admin_note' => 'Blurry ID.',
            'submitted_at' => now()->subDays(5),
            'reviewed_at' => now()->subDays(4),
        ]);
        $this->verificationFor($seller, [
            'status' => SellerVerificationStatus::Approved,
            'submitted_at' => now(),
            'reviewed_at' => now(),
        ]);
        $this->createVerification(['status' => SellerVerificationStatus::Submitted]);

        $log = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/seller-verifications?all_submissions=1');

        $log->assertOk();
        $this->assertEquals(3, $log->json('data.pagination.total'));

        // Without the option the list still narrows to each applicant's latest.
        $latest = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/seller-verifications');

        $this->assertEquals(2, $latest->json('data.pagination.total'));
    }

    public function test_submitted_equals_approved_plus_rejected_plus_pending(): void
    {
        $seller = $this->applicant();

        $this->verificationFor($seller, [
            'status' => SellerVerificationStatus::Rejected,
            'submitted_at' => now()->subDays(5),
        ]);
        $this->verificationFor($seller, [
            'status' => SellerVerificationStatus::Approved,
            'submitted_at' => now(),
        ]);
        $this->createVerification(['status' => SellerVerificationStatus::Submitted]);
        $this->createVerification(['status' => SellerVerificationStatus::PendingReview]);
        $this->createVerification(['status' => SellerVerificationStatus::Rejected]);

        $total = fn (string $query): int => $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson("/api/admin/seller-verifications?per_page=1&{$query}")
            ->json('data.pagination.total');

        $submitted = $total('all_submissions=1');
        $approved = $total('status=approved&all_submissions=1');
        $rejected = $total('status=rejected&all_submissions=1');
        $pending = $total('status=pending');

        $this->assertEquals(5, $submitted);
        $this->assertEquals(1, $approved);
        $this->assertEquals(2, $rejected);
        $this->assertEquals(2, $pending);
        $this->assertEquals($submitted, $approved + $rejected + $pending);
    }

    public function test_deciding_an_application_moves_it_out_of_pending(): void
    {
        $verification = $this->createVerification(['status' => SellerVerificationStatus::Submitted]);

        $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->postJson("/api/admin/seller-verifications/{$verification->id}/approve")
            ->assertOk();

        $pending = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/seller-verifications?status=pending');
        $this->assertEquals(0, $pending->json('data.pagination.total'));

        $log = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/seller-verifications?all_submissions=1');
        $this->assertEquals(1, $log->json('data.pagination.total'));
        $this->assertEquals('approved', $log->json('data.verifications.0.status'));
    }

    public function test_latest_record_ties_are_broken_by_id(): void
    {
        $seller = $this->applicant();
        $at = now();

        $first = $this->verificationFor($seller, ['submitted_at' => $at]);
        $second = $this->verificationFor($seller, ['submitted_at' => $at]);

        $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->postJson("/api/admin/seller-verifications/{$first->id}/approve")
            ->assertStatus(409);

        $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->postJson("/api/admin/seller-verifications/{$second->id}/approve")
            ->assertStatus(200);
    }

    public function test_show_returns_prior_submissions_as_history(): void
    {
        $seller = $this->applicant();

        $older = $this->verificationFor($seller, [
            'business_name' => 'First attempt',
            'submitted_at' => now()->subDays(5),
        ]);
        $current = $this->verificationFor($seller, [
            'business_name' => 'Second attempt',
            'submitted_at' => now(),
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson("/api/admin/seller-verifications/{$current->id}");

        $response->assertStatus(200);
        $response->assertJsonPath('data.id', $current->id);
        $response->assertJsonCount(1, 'history');
        $response->assertJsonPath('history.0.id', $older->id);
    }

    public function test_admin_surface_requires_the_admin_ability(): void
    {
        $admin = User::factory()->create([
            'role' => UserRole::Admin,
            'seller_capability' => SellerCapability::Buyer,
        ]);
        $verification = $this->createVerification();

        // A mobile-scoped token owned by an admin must still be refused.
        $token = $admin->createToken('mobile', ['mobile'])->plainTextToken;

        $this->withHeader('Authorization', "Bearer {$token}")
            ->postJson("/api/admin/seller-verifications/{$verification->id}/approve")
            ->assertStatus(403);
    }

    public function test_rejection_note_reaches_the_applicant(): void
    {
        $seller = $this->applicant();
        $verification = $this->verificationFor($seller);

        $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->postJson("/api/admin/seller-verifications/{$verification->id}/reject", [
                'admin_note' => 'The ID reference could not be verified.',
            ])
            ->assertStatus(200);

        // Sanctum caches the resolved user across requests in one test, so the
        // guard is forgotten before authenticating as a different principal.
        $this->app['auth']->forgetGuards();

        $token = $seller->createToken('mobile', ['mobile'])->plainTextToken;

        $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/seller-verification/me')
            ->assertStatus(200)
            ->assertJsonPath('data.status', SellerVerificationStatus::Rejected->value)
            ->assertJsonPath('data.admin_note', 'The ID reference could not be verified.');
    }

    public function test_admin_can_revoke_an_approved_verification(): void
    {
        $seller = User::factory()->seller()->create(['role' => UserRole::User]);
        $verification = $this->verificationFor($seller, [
            'status' => SellerVerificationStatus::Approved,
            'submitted_at' => now()->subDays(2),
            'reviewed_at' => now()->subDay(),
            'admin_note' => 'Approved originally.',
            'id_document_front_path' => 'verifications/front.jpg',
            'selfie_path' => 'verifications/selfie.jpg',
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->postJson("/api/admin/seller-verifications/{$verification->id}/revoke", [
                'admin_note' => 'Fraudulent documents were discovered after approval.',
            ]);

        $response->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.status', SellerVerificationStatus::Rejected->value)
            ->assertJsonPath('data.admin_note', 'Fraudulent documents were discovered after approval.');

        $this->assertDatabaseHas('users', [
            'id' => $seller->id,
            'seller_capability' => SellerCapability::Buyer->value,
        ]);

        $this->assertDatabaseHas('seller_verifications', [
            'id' => $verification->id,
            'status' => SellerVerificationStatus::Rejected->value,
            'reviewed_by' => $this->admin->id,
        ]);

        $revoked = $verification->fresh();
        $this->assertNotNull($revoked->reviewed_at);
        $this->assertSame('verifications/front.jpg', $revoked->id_document_front_path);
        $this->assertSame('verifications/selfie.jpg', $revoked->selfie_path);
    }

    public function test_revocation_requires_an_admin_note(): void
    {
        $seller = User::factory()->seller()->create(['role' => UserRole::User]);
        $verification = $this->verificationFor($seller, [
            'status' => SellerVerificationStatus::Approved,
            'submitted_at' => now()->subDays(2),
            'reviewed_at' => now()->subDay(),
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->postJson("/api/admin/seller-verifications/{$verification->id}/revoke");

        $response->assertStatus(422);
        $response->assertJsonValidationErrors('admin_note');

        $this->assertSame(
            SellerVerificationStatus::Approved,
            $verification->fresh()->status,
        );
        $this->assertSame(SellerCapability::Seller, $seller->fresh()->seller_capability);
    }

    public function test_only_an_approved_verification_can_be_revoked(): void
    {
        foreach ([
            SellerVerificationStatus::Submitted,
            SellerVerificationStatus::PendingReview,
            SellerVerificationStatus::Rejected,
        ] as $status) {
            $seller = User::factory()->seller()->create(['role' => UserRole::User]);
            $verification = $this->verificationFor($seller, ['status' => $status]);

            $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
                ->postJson("/api/admin/seller-verifications/{$verification->id}/revoke", [
                    'admin_note' => 'Attempted revocation.',
                ])
                ->assertStatus(409);

            $this->assertSame($status, $verification->fresh()->status);
            $this->assertSame(SellerCapability::Seller, $seller->fresh()->seller_capability);
        }
    }

    public function test_stale_approved_record_cannot_be_revoked(): void
    {
        $seller = User::factory()->seller()->create(['role' => UserRole::User]);

        $stale = $this->verificationFor($seller, [
            'status' => SellerVerificationStatus::Approved,
            'submitted_at' => now()->subDays(10),
            'reviewed_at' => now()->subDays(9),
        ]);
        $latest = $this->verificationFor($seller, [
            'status' => SellerVerificationStatus::Submitted,
            'submitted_at' => now(),
        ]);

        $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->postJson("/api/admin/seller-verifications/{$stale->id}/revoke", [
                'admin_note' => 'Attempted revocation of an older record.',
            ])
            ->assertStatus(409);

        $this->assertSame(SellerVerificationStatus::Approved, $stale->fresh()->status);
        $this->assertSame(SellerVerificationStatus::Submitted, $latest->fresh()->status);
        $this->assertSame(SellerCapability::Seller, $seller->fresh()->seller_capability);
    }

    public function test_revocation_withdraws_live_and_pending_listings_and_preserves_history(): void
    {
        $seller = User::factory()->seller()->create(['role' => UserRole::User]);
        $verification = $this->verificationFor($seller, [
            'status' => SellerVerificationStatus::Approved,
            'submitted_at' => now()->subDays(2),
            'reviewed_at' => now()->subDay(),
        ]);

        $active = $this->listingFor($seller, ListingStatus::Active);
        $pending = $this->listingFor($seller, ListingStatus::Pending);
        $draft = $this->listingFor($seller, ListingStatus::Draft);
        $sold = $this->listingFor($seller, ListingStatus::Sold);
        $inactive = $this->listingFor($seller, ListingStatus::Inactive);

        $buyer = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $transaction = Transaction::create([
            'buyer_id' => $buyer->id,
            'seller_id' => $seller->id,
            'listing_id' => $active->id,
            'quantity' => 1,
            'total_amount' => 50000.00,
            'status' => TransactionStatus::Pending,
            'inventory_reserved' => true,
        ]);

        $note = 'Fraudulent documents were discovered after approval.';

        $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->postJson("/api/admin/seller-verifications/{$verification->id}/revoke", [
                'admin_note' => $note,
            ])
            ->assertOk();

        $this->assertSame(ListingStatus::Inactive, $active->fresh()->status);
        $this->assertSame(ListingStatus::Inactive, $pending->fresh()->status);
        $this->assertSame(ListingStatus::Draft, $draft->fresh()->status);
        $this->assertSame(ListingStatus::Sold, $sold->fresh()->status);
        $this->assertSame(ListingStatus::Inactive, $inactive->fresh()->status);

        $this->assertSame($note, $pending->fresh()->admin_note);
        $this->assertSame(3, $active->fresh()->quantity);

        $this->assertDatabaseHas('transactions', [
            'id' => $transaction->id,
            'status' => TransactionStatus::Pending->value,
            'inventory_reserved' => true,
        ]);

        $this->assertDatabaseHas('activities', [
            'action' => 'seller_verification_revoked',
            'user_id' => $this->admin->id,
        ]);
        $this->assertDatabaseHas('activities', ['action' => 'listing_deactivated']);
        $this->assertDatabaseHas('activities', ['action' => 'listing_rejected']);

        $activity = Activity::query()
            ->where('action', 'seller_verification_revoked')
            ->latest('id')
            ->firstOrFail();

        $this->assertSame('approved', $activity->metadata['changes']['status']['from']);
        $this->assertSame('rejected', $activity->metadata['changes']['status']['to']);
        $this->assertSame('seller', $activity->metadata['changes']['seller_capability']['from']);
        $this->assertSame('buyer', $activity->metadata['changes']['seller_capability']['to']);
        $this->assertContains($active->id, $activity->metadata['context']['deactivated_listing_ids']);
        $this->assertContains($pending->id, $activity->metadata['context']['rejected_listing_ids']);
    }

    public function test_revocation_notifies_the_applicant(): void
    {
        Notification::fake();

        $seller = User::factory()->seller()->create(['role' => UserRole::User]);
        $verification = $this->verificationFor($seller, [
            'status' => SellerVerificationStatus::Approved,
            'submitted_at' => now()->subDays(2),
            'reviewed_at' => now()->subDay(),
        ]);

        $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->postJson("/api/admin/seller-verifications/{$verification->id}/revoke", [
                'admin_note' => 'Seller capability revoked.',
            ])
            ->assertOk();

        Notification::assertSentTo($seller, SellerVerificationRevoked::class);
    }

    public function test_revocation_requires_the_admin_ability(): void
    {
        $seller = User::factory()->seller()->create(['role' => UserRole::User]);
        $verification = $this->verificationFor($seller, [
            'status' => SellerVerificationStatus::Approved,
            'submitted_at' => now()->subDays(2),
            'reviewed_at' => now()->subDay(),
        ]);

        $token = $this->admin->createToken('mobile', ['mobile'])->plainTextToken;

        $this->withHeader('Authorization', "Bearer {$token}")
            ->postJson("/api/admin/seller-verifications/{$verification->id}/revoke", [
                'admin_note' => 'Attempted with the wrong token ability.',
            ])
            ->assertStatus(403);

        $this->assertSame(
            SellerVerificationStatus::Approved,
            $verification->fresh()->status,
        );
    }
}
