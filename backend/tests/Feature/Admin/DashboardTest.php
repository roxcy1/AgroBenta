<?php

namespace Tests\Feature\Admin;

use App\Enums\ListingStatus;
use App\Enums\SellerCapability;
use App\Enums\TransactionStatus;
use App\Enums\UserRole;
use App\Models\Activity;
use App\Models\Listing;
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
    }
}
