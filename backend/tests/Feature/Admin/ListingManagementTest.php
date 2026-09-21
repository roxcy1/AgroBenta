<?php

namespace Tests\Feature\Admin;

use App\Enums\ListingStatus;
use App\Enums\SellerCapability;
use App\Enums\UserRole;
use App\Models\Listing;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ListingManagementTest extends TestCase
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

    private function createListing(array $overrides = []): Listing
    {
        $seller = User::factory()->seller()->create(['role' => UserRole::User]);

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

    public function test_guest_cannot_access_listings(): void
    {
        $response = $this->getJson('/api/admin/listings');

        $response->assertStatus(401);
    }

    public function test_regular_user_cannot_access_listings(): void
    {
        $user = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $token = $user->createToken('user_token')->plainTextToken;

        $response = $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/admin/listings');

        $response->assertStatus(403);
    }

    public function test_admin_can_list_listings(): void
    {
        $this->createListing();
        $this->createListing(['status' => ListingStatus::Sold]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/listings');

        $response->assertStatus(200);
        $response->assertJsonStructure([
            'success',
            'data' => [
                'listings' => [
                    '*' => [
                        'id',
                        'seller',
                        'livestock_type',
                        'breed',
                        'age_value',
                        'age_unit',
                        'gender',
                        'weight_value',
                        'weight_unit',
                        'quantity',
                        'asking_price',
                        'location',
                        'health_status',
                        'vaccination',
                        'short_description',
                        'status',
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

    public function test_response_includes_seller_information(): void
    {
        $this->createListing();

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/listings');

        $response->assertStatus(200);

        $listing = $response->json('data.listings')[0];
        $this->assertArrayHasKey('id', $listing['seller']);
        $this->assertArrayHasKey('name', $listing['seller']);
        $this->assertArrayHasKey('email', $listing['seller']);
    }

    public function test_response_does_not_expose_sensitive_fields(): void
    {
        $this->createListing();

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/listings');

        $response->assertStatus(200);

        $listings = $response->json('data.listings');

        foreach ($listings as $listing) {
            $this->assertArrayNotHasKey('password', $listing);
            $this->assertArrayNotHasKey('remember_token', $listing);
        }
    }

    public function test_search_by_livestock_type(): void
    {
        $this->createListing(['livestock_type' => 'cattle']);
        $this->createListing(['livestock_type' => 'carabao']);
        $this->createListing(['livestock_type' => 'goat']);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/listings?search=cattle');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(1, $data['pagination']['total']);
        $this->assertEquals('cattle', $data['listings'][0]['livestock_type']);
    }

    public function test_search_by_breed(): void
    {
        $this->createListing(['breed' => 'Angus']);
        $this->createListing(['breed' => 'Brahman']);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/listings?search=Angus');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(1, $data['pagination']['total']);
        $this->assertEquals('Angus', $data['listings'][0]['breed']);
    }

    public function test_search_by_location(): void
    {
        $this->createListing(['location' => 'Bukidnon']);
        $this->createListing(['location' => 'Davao']);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/listings?search=Bukidnon');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(1, $data['pagination']['total']);
        $this->assertEquals('Bukidnon', $data['listings'][0]['location']);
    }

    public function test_filter_by_livestock_type(): void
    {
        $this->createListing(['livestock_type' => 'cattle']);
        $this->createListing(['livestock_type' => 'cattle']);
        $this->createListing(['livestock_type' => 'goat']);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/listings?livestock_type=cattle');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(2, $data['pagination']['total']);
    }

    public function test_filter_by_status(): void
    {
        $this->createListing(['status' => ListingStatus::Active]);
        $this->createListing(['status' => ListingStatus::Active]);
        $this->createListing(['status' => ListingStatus::Sold]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/listings?status=sold');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(1, $data['pagination']['total']);
        $this->assertEquals('sold', $data['listings'][0]['status']);
    }

    public function test_combined_search_and_filter(): void
    {
        $this->createListing(['livestock_type' => 'cattle', 'breed' => 'Angus']);
        $this->createListing(['livestock_type' => 'cattle', 'breed' => 'Brahman']);
        $this->createListing(['livestock_type' => 'goat', 'breed' => 'Angus']);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/listings?livestock_type=cattle&search=Angus');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(1, $data['pagination']['total']);
        $this->assertEquals('Angus', $data['listings'][0]['breed']);
    }

    public function test_pagination_works(): void
    {
        for ($i = 0; $i < 25; $i++) {
            $this->createListing();
        }

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/listings?per_page=10&page=1');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertCount(10, $data['listings']);
        $this->assertEquals(1, $data['pagination']['current_page']);
        $this->assertEquals(3, $data['pagination']['last_page']);
        $this->assertEquals(25, $data['pagination']['total']);
    }

    public function test_empty_search_returns_all(): void
    {
        $this->createListing();

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/listings?search=');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(1, $data['pagination']['total']);
    }

    public function test_no_listings_found_returns_empty(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/listings?search=nonexistent');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertCount(0, $data['listings']);
        $this->assertEquals(0, $data['pagination']['total']);
    }

    public function test_invalid_status_filter_returns_error(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/listings?status=invalid');

        $response->assertStatus(422);
    }

    public function test_results_are_ordered_by_created_at_desc(): void
    {
        $first = $this->createListing(['created_at' => now()->subDays(10)]);
        $second = $this->createListing(['created_at' => now()->subDays(5)]);
        $third = $this->createListing(['created_at' => now()->subDay()]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/listings');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals($third->id, $data['listings'][0]['id']);
        $this->assertEquals($second->id, $data['listings'][1]['id']);
        $this->assertEquals($first->id, $data['listings'][2]['id']);
    }
}
