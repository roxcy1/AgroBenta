<?php

namespace Tests\Feature\Admin;

use App\Enums\SellerCapability;
use App\Enums\UserRole;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class UserManagementTest extends TestCase
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

    public function test_guest_cannot_access_users(): void
    {
        $response = $this->getJson('/api/admin/users');

        $response->assertStatus(401);
    }

    public function test_regular_user_cannot_access_users(): void
    {
        $user = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $token = $user->createToken('user_token')->plainTextToken;

        $response = $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/admin/users');

        $response->assertStatus(403);
    }

    public function test_admin_can_list_users(): void
    {
        User::factory()->count(3)->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/users');

        $response->assertStatus(200);
        $response->assertJsonStructure([
            'success',
            'data' => [
                'users' => [
                    '*' => [
                        'id',
                        'name',
                        'email',
                        'role',
                        'seller_capability',
                        'email_verified_at',
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

    public function test_response_does_not_expose_sensitive_fields(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/users');

        $response->assertStatus(200);

        $users = $response->json('data.users');

        foreach ($users as $user) {
            $this->assertArrayNotHasKey('password', $user);
            $this->assertArrayNotHasKey('remember_token', $user);
        }
    }

    public function test_admin_user_is_included_in_results(): void
    {
        User::factory()->count(2)->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/users');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(3, $data['pagination']['total']);
    }

    public function test_search_by_name(): void
    {
        User::factory()->create(['name' => 'Juan Dela Cruz']);
        User::factory()->create(['name' => 'Maria Santos']);
        User::factory()->create(['name' => 'Jose Rizal']);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/users?search=Juan');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(1, $data['pagination']['total']);
        $this->assertEquals('Juan Dela Cruz', $data['users'][0]['name']);
    }

    public function test_search_by_email(): void
    {
        User::factory()->create(['email' => 'juan@example.com']);
        User::factory()->create(['email' => 'maria@example.com']);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/users?search=juan@');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(1, $data['pagination']['total']);
        $this->assertEquals('juan@example.com', $data['users'][0]['email']);
    }

    public function test_filter_by_role(): void
    {
        User::factory()->create(['role' => UserRole::User, 'seller_capability' => SellerCapability::Buyer]);
        User::factory()->create(['role' => UserRole::User, 'seller_capability' => SellerCapability::Buyer]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/users?role=admin');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(1, $data['pagination']['total']);
        $this->assertEquals('admin', $data['users'][0]['role']);
    }

    public function test_filter_by_seller_capability(): void
    {
        User::factory()->create(['role' => UserRole::User, 'seller_capability' => SellerCapability::Buyer]);
        User::factory()->seller()->create(['role' => UserRole::User]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/users?seller_capability=seller');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(1, $data['pagination']['total']);
        $this->assertEquals('seller', $data['users'][0]['seller_capability']);
    }

    public function test_combined_search_and_filters(): void
    {
        User::factory()->create(['name' => 'Juan', 'role' => UserRole::User, 'seller_capability' => SellerCapability::Buyer]);
        User::factory()->create(['name' => 'Juan', 'role' => UserRole::User, 'seller_capability' => SellerCapability::Seller]);
        User::factory()->create(['name' => 'Maria', 'role' => UserRole::User, 'seller_capability' => SellerCapability::Buyer]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/users?search=Juan&seller_capability=seller');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(1, $data['pagination']['total']);
        $this->assertEquals('Juan', $data['users'][0]['name']);
        $this->assertEquals('seller', $data['users'][0]['seller_capability']);
    }

    public function test_pagination_works(): void
    {
        User::factory()->count(24)->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/users?per_page=10&page=1');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertCount(10, $data['users']);
        $this->assertEquals(1, $data['pagination']['current_page']);
        $this->assertEquals(3, $data['pagination']['last_page']);
        $this->assertEquals(25, $data['pagination']['total']);
    }

    public function test_pagination_page_2(): void
    {
        User::factory()->count(25)->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/users?per_page=10&page=2');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertCount(10, $data['users']);
        $this->assertEquals(2, $data['pagination']['current_page']);
    }

    public function test_empty_search_returns_all(): void
    {
        User::factory()->count(3)->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/users?search=');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(4, $data['pagination']['total']);
    }

    public function test_no_users_found_returns_empty(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/users?search=nonexistent');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertCount(0, $data['users']);
        $this->assertEquals(0, $data['pagination']['total']);
    }

    public function test_invalid_role_filter_returns_error(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/users?role=superadmin');

        $response->assertStatus(422);
    }

    public function test_invalid_seller_capability_filter_returns_error(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/users?seller_capability=merchant');

        $response->assertStatus(422);
    }

    public function test_results_are_ordered_by_created_at_desc(): void
    {
        $first = User::factory()->create([
            'name' => 'First User',
            'created_at' => now()->subDays(10),
        ]);
        $second = User::factory()->create([
            'name' => 'Second User',
            'created_at' => now()->subDays(5),
        ]);
        $third = User::factory()->create([
            'name' => 'Third User',
            'created_at' => now()->subDay(),
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/users');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals('Third User', $data['users'][0]['name']);
        $this->assertEquals('Second User', $data['users'][1]['name']);
        $this->assertEquals('First User', $data['users'][2]['name']);
    }
}
