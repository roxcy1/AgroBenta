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
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class DashboardTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();

        $this->admin = User::factory()->create([
            'role' => UserRole::Admin,
            'seller_capability' => SellerCapability::Buyer,
        ]);
    }

    public function test_guest_cannot_access_dashboard(): void
    {
        $response = $this->getJson('/api/admin/dashboard');

        $response->assertStatus(401);
    }

    public function test_regular_user_cannot_access_dashboard(): void
    {
        $user = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $token = $user->createToken('user_token')->plainTextToken;

        $response = $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/admin/dashboard');

        $response->assertStatus(403);
    }

    public function test_admin_can_access_dashboard(): void
    {
        $token = $this->admin->createToken('admin_token', ['admin'])->plainTextToken;

        $response = $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/admin/dashboard');

        $response->assertStatus(200);
        $response->assertJsonStructure([
            'success',
            'data' => [
                'summary' => [
                    'total_users',
                    'buyer_accounts',
                    'approved_sellers',
                    'total_listings',
                    'active_listings',
                    'total_transactions',
                    'pending_verifications',
                ],
                'listings' => [
                    'total',
                    'active',
                    'sold',
                    'pending',
                    'draft',
                    'inactive',
                ],
                'transactions' => [
                    'total',
                    'pending',
                    'completed',
                    'cancelled',
                ],
                'transaction_trend',
                'livestock_distribution',
                'recent_activities',
                'recent_listings',
                'recent_transactions',
            ],
        ]);
    }

    public function test_dashboard_returns_zero_values_for_empty_database(): void
    {
        $token = $this->admin->createToken('admin_token', ['admin'])->plainTextToken;

        $response = $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/admin/dashboard');

        $response->assertStatus(200);
        $response->assertJson([
            'success' => true,
            'data' => [
                'summary' => [
                    'total_users' => 1,
                    'buyer_accounts' => 0,
                    'approved_sellers' => 0,
                    'total_listings' => 0,
                    'active_listings' => 0,
                    'total_transactions' => 0,
                    'pending_verifications' => 0,
                ],
                'listings' => [
                    'total' => 0,
                    'active' => 0,
                    'sold' => 0,
                    'pending' => 0,
                    'draft' => 0,
                    'inactive' => 0,
                ],
                'transactions' => [
                    'total' => 0,
                    'pending' => 0,
                    'completed' => 0,
                    'cancelled' => 0,
                ],
                'recent_activities' => [],
                'recent_listings' => [],
                'recent_transactions' => [],
            ],
        ]);
    }

    public function test_dashboard_values_reflect_actual_data(): void
    {
        $buyer = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $seller = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Seller,
        ]);

        $listingData = [
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
            'location' => 'Bukidnon',
            'health_status' => 'healthy',
            'vaccination' => 'up_to_date',
            'short_description' => 'Healthy Angus bull',
            'photos' => [],
        ];

        Listing::create(array_merge($listingData, ['status' => ListingStatus::Active]));
        Listing::create(array_merge($listingData, ['status' => ListingStatus::Active]));
        Listing::create(array_merge($listingData, ['status' => ListingStatus::Active]));
        Listing::create(array_merge($listingData, ['status' => ListingStatus::Sold]));
        Listing::create(array_merge($listingData, ['status' => ListingStatus::Sold]));

        Transaction::create([
            'buyer_id' => $buyer->id,
            'seller_id' => $seller->id,
            'listing_id' => Listing::first()->id,
            'quantity' => 1,
            'total_amount' => 50000.00,
            'status' => TransactionStatus::Completed,
        ]);

        Transaction::create([
            'buyer_id' => $buyer->id,
            'seller_id' => $seller->id,
            'listing_id' => Listing::first()->id,
            'quantity' => 1,
            'total_amount' => 50000.00,
            'status' => TransactionStatus::Pending,
        ]);

        Activity::create([
            'user_id' => $seller->id,
            'action' => 'listing_created',
            'description' => 'Created a new livestock listing',
        ]);

        $token = $this->admin->createToken('admin_token', ['admin'])->plainTextToken;

        $response = $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/admin/dashboard');

        $response->assertStatus(200);

        $data = $response->json('data');

        $this->assertEquals(3, $data['summary']['total_users']);
        $this->assertEquals(1, $data['summary']['buyer_accounts']);
        $this->assertEquals(1, $data['summary']['approved_sellers']);
        $this->assertEquals(5, $data['summary']['total_listings']);
        $this->assertEquals(3, $data['summary']['active_listings']);
        $this->assertEquals(2, $data['summary']['total_transactions']);

        $this->assertEquals(5, $data['listings']['total']);
        $this->assertEquals(3, $data['listings']['active']);
        $this->assertEquals(2, $data['listings']['sold']);

        $this->assertEquals(2, $data['transactions']['total']);
        $this->assertEquals(1, $data['transactions']['pending']);
        $this->assertEquals(1, $data['transactions']['completed']);

        $this->assertCount(1, $data['recent_activities']);
        $this->assertEquals('listing_created', $data['recent_activities'][0]['action']);

        $this->assertCount(5, $data['recent_listings']);
        $this->assertEquals(Listing::orderByDesc('id')->first()->id, $data['recent_listings'][0]['id']);
        $this->assertEquals('cattle', $data['recent_listings'][0]['livestock_type']);
        $this->assertEquals('Angus', $data['recent_listings'][0]['breed']);
        $this->assertEquals($seller->name, $data['recent_listings'][0]['seller']['name']);

        $this->assertCount(2, $data['recent_transactions']);
        $this->assertEquals(Transaction::orderByDesc('id')->first()->id, $data['recent_transactions'][0]['id']);
        $this->assertEquals($buyer->name, $data['recent_transactions'][0]['buyer']['name']);
        $this->assertEquals($seller->name, $data['recent_transactions'][0]['seller']['name']);
        $this->assertEquals('cattle', $data['recent_transactions'][0]['listing']['livestock_type']);
    }

    public function test_dashboard_counts_pending_verifications_from_latest_record_only(): void
    {
        $applicant = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $other = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $decision = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Seller,
        ]);

        // The applicant's older submission is pending, but a newer approved
        // record supersedes it, so the applicant must not count as pending.
        SellerVerification::create([
            'user_id' => $applicant->id,
            'business_name' => 'Superseded Farm',
            'status' => SellerVerificationStatus::PendingReview,
            'submitted_at' => now()->subDay(),
        ]);

        SellerVerification::create([
            'user_id' => $applicant->id,
            'business_name' => 'Latest Farm',
            'status' => SellerVerificationStatus::Approved,
            'submitted_at' => now(),
        ]);

        // This applicant's only (and therefore latest) record is pending.
        SellerVerification::create([
            'user_id' => $other->id,
            'business_name' => 'Pending Farm',
            'status' => SellerVerificationStatus::PendingReview,
            'submitted_at' => now(),
        ]);

        // A terminal record must never be counted as pending.
        SellerVerification::create([
            'user_id' => $decision->id,
            'business_name' => 'Rejected Farm',
            'status' => SellerVerificationStatus::Rejected,
            'submitted_at' => now(),
        ]);

        $token = $this->admin->createToken('admin_token', ['admin'])->plainTextToken;

        $response = $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/admin/dashboard');

        $response->assertStatus(200);
        $this->assertEquals(1, $response->json('data.summary.pending_verifications'));
    }

    public function test_dashboard_recent_sections_are_limited_and_newest_first(): void
    {
        $buyer = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $seller = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Seller,
        ]);

        $listings = [];
        for ($i = 1; $i <= 7; $i++) {
            $listing = $this->createListing($seller, ['breed' => "Breed {$i}"]);
            $listing->forceFill([
                'created_at' => now()->subDays(8 - $i),
                'updated_at' => now()->subDays(8 - $i),
            ])->save();

            $listings[$i] = $listing;
        }

        $transactions = [];
        for ($i = 1; $i <= 6; $i++) {
            $transaction = Transaction::create([
                'buyer_id' => $buyer->id,
                'seller_id' => $seller->id,
                'listing_id' => $listings[1]->id,
                'quantity' => $i,
                'total_amount' => 1000.00 * $i,
                'status' => TransactionStatus::Pending,
            ]);
            $transaction->forceFill([
                'created_at' => now()->subDays(7 - $i),
                'updated_at' => now()->subDays(7 - $i),
            ])->save();

            $transactions[$i] = $transaction;
        }

        $token = $this->admin->createToken('admin_token', ['admin'])->plainTextToken;

        $response = $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/admin/dashboard');

        $response->assertStatus(200);

        $recentListings = $response->json('data.recent_listings');
        $this->assertCount(5, $recentListings);
        $this->assertEquals($listings[7]->id, $recentListings[0]['id']);
        $this->assertEquals($listings[3]->id, $recentListings[4]['id']);

        $recentTransactions = $response->json('data.recent_transactions');
        $this->assertCount(5, $recentTransactions);
        $this->assertEquals($transactions[6]->id, $recentTransactions[0]['id']);
        $this->assertEquals($transactions[2]->id, $recentTransactions[4]['id']);
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
            'location' => 'Bukidnon',
            'health_status' => 'healthy',
            'vaccination' => 'up_to_date',
            'short_description' => 'Healthy Angus bull',
            'photos' => [],
            'status' => ListingStatus::Active,
        ], $overrides));
    }
}
