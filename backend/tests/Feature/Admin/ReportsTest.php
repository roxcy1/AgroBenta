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
use Illuminate\Contracts\Auth\Factory;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ReportsTest extends TestCase
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

    private function createListing(?string $status = null): Listing
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
            'status' => $status ? ListingStatus::from($status) : ListingStatus::Active,
        ]);
    }

    public function test_guest_cannot_access_reports(): void
    {
        $response = $this->getJson('/api/admin/reports');

        $response->assertStatus(401);
    }

    public function test_regular_user_cannot_access_reports(): void
    {
        $token = $this->buyer->createToken('user_token')->plainTextToken;

        $response = $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/admin/reports');

        $response->assertStatus(403);
    }

    public function test_admin_can_access_reports(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/reports');

        $response->assertStatus(200);
        $response->assertJsonStructure([
            'success',
            'data' => [
                'overview',
                'users',
                'listings',
                'transactions',
                'seller_verifications',
                'activities',
            ],
        ]);
    }

    public function test_overview_returns_real_database_aggregates(): void
    {
        $listing = $this->createListing('active');

        Transaction::create([
            'buyer_id' => $this->buyer->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'quantity' => 1,
            'total_amount' => 50000.00,
            'status' => TransactionStatus::Completed,
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/reports');

        $response->assertStatus(200);

        $overview = $response->json('data.overview');
        $this->assertEquals(3, $overview['total_users']);
        $this->assertEquals(1, $overview['buyer_accounts']);
        $this->assertEquals(1, $overview['approved_sellers']);
        $this->assertEquals(1, $overview['total_listings']);
        $this->assertEquals(1, $overview['active_listings']);
        $this->assertEquals(1, $overview['total_transactions']);
    }

    public function test_user_report_returns_expected_data(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/reports');

        $response->assertStatus(200);

        $users = $response->json('data.users');
        $this->assertEquals(3, $users['total']);
        $this->assertEquals(1, $users['buyers']);
        $this->assertEquals(1, $users['sellers']);
        $this->assertEquals(1, $users['admins']);
        $this->assertArrayHasKey('registration_trend', $users);
        $this->assertArrayHasKey('seller_distribution', $users);
    }

    public function test_listing_report_returns_expected_data(): void
    {
        $this->createListing('active');
        $this->createListing('sold');

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/reports');

        $response->assertStatus(200);

        $listings = $response->json('data.listings');
        $this->assertEquals(2, $listings['total']);
        $this->assertEquals(1, $listings['active']);
        $this->assertEquals(1, $listings['sold']);
        $this->assertArrayHasKey('by_type', $listings);
        $this->assertArrayHasKey('by_status', $listings);
        $this->assertArrayHasKey('price_stats', $listings);
    }

    public function test_transaction_report_returns_expected_data(): void
    {
        $listing = $this->createListing();

        Transaction::create([
            'buyer_id' => $this->buyer->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'quantity' => 1,
            'total_amount' => 50000.00,
            'status' => TransactionStatus::Completed,
        ]);

        Transaction::create([
            'buyer_id' => $this->buyer->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'quantity' => 1,
            'total_amount' => 30000.00,
            'status' => TransactionStatus::Pending,
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/reports');

        $response->assertStatus(200);

        $transactions = $response->json('data.transactions');
        $this->assertEquals(2, $transactions['total']);
        $this->assertEquals(1, $transactions['completed']);
        $this->assertEquals(1, $transactions['pending']);
        $this->assertEquals(50000.00, $transactions['total_revenue']);
        $this->assertArrayHasKey('trend', $transactions);
        $this->assertArrayHasKey('by_status', $transactions);
        $this->assertArrayHasKey('by_livestock', $transactions);
    }

    public function test_seller_verification_report_returns_expected_data(): void
    {
        SellerVerification::create([
            'user_id' => $this->buyer->id,
            'business_name' => 'Test Business',
            'status' => SellerVerificationStatus::Approved,
            'submitted_at' => now(),
        ]);

        SellerVerification::create([
            'user_id' => $this->seller->id,
            'business_name' => 'Another Business',
            'status' => SellerVerificationStatus::Rejected,
            'submitted_at' => now(),
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/reports');

        $response->assertStatus(200);

        $verifications = $response->json('data.seller_verifications');
        $this->assertEquals(2, $verifications['total']);
        $this->assertEquals(1, $verifications['approved']);
        $this->assertEquals(1, $verifications['rejected']);
        $this->assertArrayHasKey('submission_trend', $verifications);
        $this->assertArrayHasKey('status_distribution', $verifications);
    }

    public function test_activity_report_returns_expected_data(): void
    {
        Activity::create([
            'user_id' => $this->buyer->id,
            'action' => 'listing_created',
            'description' => 'Created a listing',
        ]);

        Activity::create([
            'user_id' => $this->seller->id,
            'action' => 'transaction_completed',
            'description' => 'Completed a transaction',
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/reports');

        $response->assertStatus(200);

        $activities = $response->json('data.activities');
        $this->assertEquals(2, $activities['total']);
        $this->assertArrayHasKey('by_action', $activities);
        $this->assertArrayHasKey('trend', $activities);
        $this->assertArrayHasKey('by_user', $activities);
    }

    public function test_date_filtering_works(): void
    {
        $listing = $this->createListing();

        Transaction::forceCreate([
            'buyer_id' => $this->buyer->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'quantity' => 1,
            'total_amount' => 50000.00,
            'status' => TransactionStatus::Completed,
            'created_at' => now()->subDays(5),
        ]);

        Transaction::forceCreate([
            'buyer_id' => $this->buyer->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'quantity' => 1,
            'total_amount' => 30000.00,
            'status' => TransactionStatus::Pending,
            'created_at' => now()->subDays(2),
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/reports?date_from='.now()->subDays(3)->format('Y-m-d'));

        $response->assertStatus(200);

        $transactions = $response->json('data.transactions');
        $this->assertEquals(1, $transactions['total']);
    }

    public function test_invalid_date_range_is_rejected(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/reports?date_from=2026-12-31&date_to=2026-01-01');

        $response->assertStatus(422);
    }

    public function test_empty_dataset_returns_valid_zero_structures(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/reports');

        $response->assertStatus(200);

        $data = $response->json('data');

        $this->assertEquals(3, $data['overview']['total_users']);
        $this->assertEquals(0, $data['overview']['total_listings']);
        $this->assertEquals(0, $data['overview']['total_transactions']);
        $this->assertEquals(3, $data['users']['total']);
        $this->assertEquals(0, $data['listings']['total']);
        $this->assertEquals(0, $data['transactions']['total']);
        $this->assertEquals(0, $data['seller_verifications']['total']);
        $this->assertEquals(0, $data['activities']['total']);
    }

    public function test_sensitive_fields_are_not_exposed(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/reports');

        $response->assertStatus(200);

        $overview = $response->json('data.overview');
        $this->assertArrayNotHasKey('password', $overview);
        $this->assertArrayNotHasKey('remember_token', $overview);
    }

    public function test_authorization_remains_enforced(): void
    {
        $response = $this->getJson('/api/admin/reports');
        $response->assertStatus(401);

        $token = $this->buyer->createToken('user_token')->plainTextToken;
        $response = $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/admin/reports');
        $response->assertStatus(403);

        app(Factory::class)->forgetGuards();

        $adminToken = $this->adminToken();

        $response = $this->withHeader('Authorization', "Bearer {$adminToken}")
            ->getJson('/api/admin/reports');
        $response->assertStatus(200);
    }
}
