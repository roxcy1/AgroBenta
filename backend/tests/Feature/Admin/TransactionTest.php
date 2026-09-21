<?php

namespace Tests\Feature\Admin;

use App\Enums\ListingStatus;
use App\Enums\SellerCapability;
use App\Enums\TransactionStatus;
use App\Enums\UserRole;
use App\Models\Listing;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class TransactionTest extends TestCase
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

    public function test_guest_cannot_access_transactions(): void
    {
        $response = $this->getJson('/api/admin/transactions');

        $response->assertStatus(401);
    }

    public function test_regular_user_cannot_access_transactions(): void
    {
        $token = $this->buyer->createToken('user_token')->plainTextToken;

        $response = $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/admin/transactions');

        $response->assertStatus(403);
    }

    public function test_admin_can_access_transactions(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/transactions');

        $response->assertStatus(200);
        $response->assertJsonStructure([
            'success',
            'data' => [
                'transactions' => [],
                'pagination' => [
                    'current_page',
                    'last_page',
                    'per_page',
                    'total',
                ],
            ],
        ]);
    }

    public function test_transactions_are_returned(): void
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
            'quantity' => 2,
            'total_amount' => 100000.00,
            'status' => TransactionStatus::Pending,
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/transactions');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(2, $data['pagination']['total']);
        $this->assertCount(2, $data['transactions']);
    }

    public function test_search_works(): void
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

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/transactions?search='.$this->buyer->name);

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(1, $data['pagination']['total']);
    }

    public function test_status_filter_works(): void
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
            'total_amount' => 50000.00,
            'status' => TransactionStatus::Pending,
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/transactions?status=completed');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(1, $data['pagination']['total']);
        $this->assertEquals('completed', $data['transactions'][0]['status']);
    }

    public function test_date_filtering_works(): void
    {
        $listing = $this->createListing();

        Transaction::create([
            'buyer_id' => $this->buyer->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'quantity' => 1,
            'total_amount' => 50000.00,
            'status' => TransactionStatus::Completed,
            'created_at' => now()->subDays(10),
        ]);

        Transaction::create([
            'buyer_id' => $this->buyer->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'quantity' => 1,
            'total_amount' => 50000.00,
            'status' => TransactionStatus::Pending,
            'created_at' => now()->subDays(2),
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/transactions?date_from='.now()->subDays(5)->format('Y-m-d'));

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(1, $data['pagination']['total']);
    }

    public function test_pagination_works(): void
    {
        $listing = $this->createListing();

        Transaction::factory()->count(24)->create([
            'buyer_id' => $this->buyer->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'status' => TransactionStatus::Pending,
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/transactions?per_page=10&page=1');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertCount(10, $data['transactions']);
        $this->assertEquals(1, $data['pagination']['current_page']);
        $this->assertEquals(3, $data['pagination']['last_page']);
        $this->assertEquals(25, $data['pagination']['total']);
    }

    public function test_empty_search_returns_empty(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/transactions?search=nonexistent');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertCount(0, $data['transactions']);
        $this->assertEquals(0, $data['pagination']['total']);
    }

    public function test_empty_state_works(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/transactions');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertCount(0, $data['transactions']);
        $this->assertEquals(0, $data['pagination']['total']);
    }

    public function test_response_does_not_expose_sensitive_fields(): void
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

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/transactions');

        $response->assertStatus(200);

        $transactions = $response->json('data.transactions');
        $this->assertNotEmpty($transactions);

        foreach ($transactions as $transaction) {
            $this->assertArrayNotHasKey('buyer_id', $transaction);
            $this->assertArrayNotHasKey('seller_id', $transaction);
            $this->assertArrayNotHasKey('listing_id', $transaction);
        }
    }

    public function test_invalid_status_filter_returns_error(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/transactions?status=invalid');

        $response->assertStatus(422);
    }

    public function test_results_are_ordered_by_created_at_desc(): void
    {
        $listing = $this->createListing();

        $first = Transaction::create([
            'buyer_id' => $this->buyer->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'quantity' => 1,
            'total_amount' => 50000.00,
            'status' => TransactionStatus::Completed,
            'created_at' => now()->subDays(10),
        ]);

        $second = Transaction::create([
            'buyer_id' => $this->buyer->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'quantity' => 1,
            'total_amount' => 50000.00,
            'status' => TransactionStatus::Pending,
            'created_at' => now()->subDays(5),
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/transactions');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals($second->id, $data['transactions'][0]['id']);
        $this->assertEquals($first->id, $data['transactions'][1]['id']);
    }
}
