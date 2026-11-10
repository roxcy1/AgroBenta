<?php

namespace Tests\Feature\Admin;

use App\Enums\ListingStatus;
use App\Enums\SellerCapability;
use App\Enums\SellerVerificationStatus;
use App\Enums\TransactionStatus;
use App\Enums\UserRole;
use App\Models\Activity;
use App\Models\Listing;
use App\Models\Message;
use App\Models\SellerVerification;
use App\Models\Transaction;
use App\Models\User;
use App\Services\Admin\AdminUserService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpKernel\Exception\HttpException;
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

    public function test_admin_can_show_a_single_user(): void
    {
        $user = User::factory()->create([
            'name' => 'Juan Dela Cruz',
            'email' => 'juan@example.com',
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Seller,
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson("/api/admin/users/{$user->id}");

        $response->assertStatus(200);
        $response->assertJsonPath('success', true);
        $response->assertJsonPath('data.id', $user->id);
        $response->assertJsonPath('data.email', 'juan@example.com');
        $response->assertJsonStructure([
            'data' => [
                'id',
                'name',
                'email',
                'role',
                'seller_capability',
                'email_verified_at',
                'created_at',
                'updated_at',
            ],
        ]);
    }

    public function test_show_does_not_expose_sensitive_fields(): void
    {
        $user = User::factory()->create();

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson("/api/admin/users/{$user->id}");

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertArrayNotHasKey('password', $data);
        $this->assertArrayNotHasKey('remember_token', $data);
    }

    public function test_guest_cannot_show_a_single_user(): void
    {
        $response = $this->getJson('/api/admin/users/1');

        $response->assertStatus(401);
    }

    public function test_regular_user_cannot_show_a_single_user(): void
    {
        $user = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $token = $user->createToken('user_token')->plainTextToken;

        $response = $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson("/api/admin/users/{$user->id}");

        $response->assertStatus(403);
    }

    public function test_show_returns_not_found_for_missing_user(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/users/999999');

        $response->assertStatus(404);
    }

    public function test_admin_can_update_only_a_users_name_and_email(): void
    {
        $user = User::factory()->create([
            'name' => 'Original Name',
            'email' => 'original@example.com',
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->putJson("/api/admin/users/{$user->id}", [
                'name' => 'Updated Name',
                'email' => 'updated@example.com',
            ]);

        $response->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.id', $user->id)
            ->assertJsonPath('data.name', 'Updated Name')
            ->assertJsonPath('data.email', 'updated@example.com');
        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'name' => 'Updated Name',
            'email' => 'updated@example.com',
            'role' => UserRole::User->value,
            'seller_capability' => SellerCapability::Buyer->value,
        ]);
        $this->assertDatabaseHas('activities', [
            'user_id' => $this->admin->id,
            'action' => 'admin_user_updated',
        ]);
    }

    public function test_updating_a_users_email_to_its_own_value_is_allowed(): void
    {
        $user = User::factory()->create(['email' => 'same@example.com']);

        $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->putJson("/api/admin/users/{$user->id}", [
                'name' => $user->name,
                'email' => $user->email,
            ])
            ->assertOk();
    }

    public function test_duplicate_email_is_rejected(): void
    {
        $user = User::factory()->create();
        $other = User::factory()->create(['email' => 'taken@example.com']);

        $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->putJson("/api/admin/users/{$user->id}", [
                'name' => 'New Name',
                'email' => $other->email,
            ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('email');

        $this->assertDatabaseHas('users', ['id' => $user->id, 'name' => $user->name]);
    }

    public function test_invalid_name_or_email_is_rejected(): void
    {
        $user = User::factory()->create();

        $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->putJson("/api/admin/users/{$user->id}", [
                'name' => '  ',
                'email' => 'not-an-email',
            ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['name', 'email']);
    }

    public function test_server_owned_user_fields_cannot_be_edited(): void
    {
        $user = User::factory()->create();

        $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->putJson("/api/admin/users/{$user->id}", [
                'name' => 'Changed Name',
                'email' => $user->email,
                'role' => UserRole::Admin->value,
            ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('role');

        $this->assertSame(UserRole::User, $user->fresh()->role);
    }

    public function test_guest_and_non_admin_cannot_update_or_delete_users(): void
    {
        $user = User::factory()->create();

        $this->putJson("/api/admin/users/{$user->id}", [
            'name' => 'Changed',
            'email' => $user->email,
        ])->assertUnauthorized();
        $this->deleteJson("/api/admin/users/{$user->id}")->assertUnauthorized();

        $regular = User::factory()->create();
        $regularToken = $regular->createToken('mobile', ['mobile'])->plainTextToken;
        $this->withHeader('Authorization', "Bearer {$regularToken}")
            ->putJson("/api/admin/users/{$user->id}", [
                'name' => 'Changed',
                'email' => $user->email,
            ])->assertForbidden();
        $this->withHeader('Authorization', "Bearer {$regularToken}")
            ->deleteJson("/api/admin/users/{$user->id}")->assertForbidden();
    }

    public function test_admin_cannot_delete_their_own_account(): void
    {
        $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->deleteJson("/api/admin/users/{$this->admin->id}")
            ->assertStatus(409)
            ->assertJsonPath('message', 'Administrators cannot delete their own account.');

        $this->assertDatabaseHas('users', [
            'id' => $this->admin->id,
            'deleted_at' => null,
        ]);
    }

    public function test_admin_can_delete_another_administrator_when_one_remains(): void
    {
        $otherAdmin = User::factory()->admin()->create();
        $otherAdminToken = $otherAdmin->createToken('admin_token', ['admin'])->plainTextToken;

        $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->deleteJson("/api/admin/users/{$otherAdmin->id}")
            ->assertOk();

        $this->assertSoftDeleted('users', ['id' => $otherAdmin->id]);
        $this->assertSame(1, User::query()->where('role', UserRole::Admin)->count());
        $this->withHeader('Authorization', "Bearer {$otherAdminToken}")
            ->getJson('/api/admin/auth/me')
            ->assertUnauthorized();
    }

    public function test_last_active_administrator_guard_refuses_deactivation(): void
    {
        $otherActor = User::factory()->create(['role' => UserRole::User]);
        $service = $this->app->make(AdminUserService::class);

        try {
            $service->deleteUser($this->admin, $otherActor);
            $this->fail('The last active administrator should be protected.');
        } catch (HttpException $exception) {
            $this->assertSame(409, $exception->getStatusCode());
            $this->assertSame('The last active administrator cannot be deleted.', $exception->getMessage());
        }

        $this->assertDatabaseHas('users', [
            'id' => $this->admin->id,
            'deleted_at' => null,
        ]);
    }

    public function test_admin_can_soft_delete_user_preserving_history_and_revoking_sessions(): void
    {
        $user = User::factory()->seller()->create([
            'role' => UserRole::User,
            'name' => 'Inactive Seller',
            'email' => 'inactive-seller@example.com',
        ]);
        $buyer = User::factory()->create();
        $listing = Listing::create([
            'seller_id' => $user->id,
            'livestock_type' => 'cattle',
            'breed' => 'Angus',
            'quantity' => 1,
            'asking_price' => 1000,
            'location' => 'Purok 1, Barangay Poblacion, Trinidad, Bohol',
            'short_description' => 'Listing retained for history.',
            'photos' => [],
            'status' => ListingStatus::Active,
        ]);
        $verification = SellerVerification::create([
            'user_id' => $user->id,
            'phone' => '09171234567',
            'address' => 'Purok 1, Barangay Poblacion, Trinidad, Bohol',
            'business_name' => 'Inactive Seller Farm',
            'status' => SellerVerificationStatus::Approved,
            'submitted_at' => now(),
        ]);
        $transaction = Transaction::create([
            'buyer_id' => $buyer->id,
            'seller_id' => $user->id,
            'listing_id' => $listing->id,
            'quantity' => 1,
            'total_amount' => 1000,
            'status' => TransactionStatus::Completed,
        ]);
        $message = Message::create([
            'sender_id' => $user->id,
            'receiver_id' => $buyer->id,
            'body' => 'Historical message.',
        ]);
        $activity = Activity::create([
            'user_id' => $user->id,
            'action' => 'user_logged_in',
            'description' => 'Historical activity.',
        ]);
        DB::table('sessions')->insert([
            'id' => 'inactive-user-session',
            'user_id' => $user->id,
            'payload' => 'test-session',
            'last_activity' => time(),
        ]);
        $mobileToken = $user->createToken('mobile', ['mobile'])->plainTextToken;
        $adminToken = $this->adminToken();

        $this->withHeader('Authorization', "Bearer {$adminToken}")
            ->deleteJson("/api/admin/users/{$user->id}")
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.id', $user->id);

        $this->assertSoftDeleted('users', ['id' => $user->id]);
        $this->assertDatabaseHas('listings', ['id' => $listing->id, 'status' => ListingStatus::Active->value]);
        $this->assertDatabaseHas('seller_verifications', ['id' => $verification->id]);
        $this->assertDatabaseHas('transactions', ['id' => $transaction->id, 'status' => TransactionStatus::Completed->value]);
        $this->assertDatabaseHas('messages', ['id' => $message->id, 'body' => 'Historical message.']);
        $this->assertDatabaseHas('activities', ['id' => $activity->id, 'user_id' => $user->id]);
        $this->assertDatabaseHas('activities', [
            'user_id' => $this->admin->id,
            'action' => 'admin_user_deleted',
        ]);
        $this->assertDatabaseMissing('sessions', ['id' => 'inactive-user-session']);

        $adminHeader = ['Authorization' => "Bearer {$adminToken}"];
        $this->withHeaders($adminHeader)
            ->getJson('/api/admin/listings')
            ->assertOk()
            ->assertJsonPath('data.listings.0.seller.name', 'Inactive Seller');
        $this->withHeaders($adminHeader)
            ->getJson('/api/admin/activities?search=Historical')
            ->assertOk()
            ->assertJsonPath('data.activities.0.user.name', 'Inactive Seller');

        $this->withHeader('Authorization', "Bearer {$mobileToken}")
            ->getJson('/api/user')
            ->assertUnauthorized();

        $this->withHeader('Authorization', "Bearer {$adminToken}")
            ->getJson('/api/admin/users')
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 2);

        $this->withHeader('Authorization', "Bearer {$adminToken}")
            ->deleteJson("/api/admin/users/{$user->id}")
            ->assertNotFound();
    }

    public function test_deleted_sellers_active_listings_are_hidden_without_changing_status(): void
    {
        $seller = User::factory()->seller()->create(['role' => UserRole::User]);
        $listing = Listing::create([
            'seller_id' => $seller->id,
            'livestock_type' => 'cattle',
            'breed' => 'Angus',
            'quantity' => 1,
            'asking_price' => 1000,
            'location' => 'Purok 1, Barangay Poblacion, Trinidad, Bohol',
            'short_description' => 'Hidden listing.',
            'photos' => [],
            'status' => ListingStatus::Active,
        ]);
        $buyer = User::factory()->create();
        $buyerToken = $buyer->createToken('mobile', ['mobile'])->plainTextToken;

        $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->deleteJson("/api/admin/users/{$seller->id}")
            ->assertOk();

        $this->withHeader('Authorization', "Bearer {$buyerToken}")
            ->getJson('/api/listings')
            ->assertOk()
            ->assertJsonMissing(['id' => $listing->id]);

        $this->withHeader('Authorization', "Bearer {$buyerToken}")
            ->postJson('/api/transactions', [
                'listing_id' => $listing->id,
                'quantity' => 1,
            ])
            ->assertStatus(409);

        $this->assertDatabaseHas('listings', [
            'id' => $listing->id,
            'status' => ListingStatus::Active->value,
        ]);
    }

    public function test_deleted_counterpart_remains_visible_in_financial_history(): void
    {
        $seller = User::factory()->seller()->create([
            'role' => UserRole::User,
            'name' => 'Historical Seller',
            'email' => 'historical@example.com',
        ]);
        $buyer = User::factory()->create();
        $listing = Listing::create([
            'seller_id' => $seller->id,
            'livestock_type' => 'cattle',
            'breed' => 'Angus',
            'quantity' => 1,
            'asking_price' => 1000,
            'location' => 'Purok 1, Barangay Poblacion, Trinidad, Bohol',
            'short_description' => 'Sold listing.',
            'photos' => [],
            'status' => ListingStatus::Sold,
        ]);
        $transaction = Transaction::create([
            'buyer_id' => $buyer->id,
            'seller_id' => $seller->id,
            'listing_id' => $listing->id,
            'quantity' => 1,
            'total_amount' => 1000,
            'status' => TransactionStatus::Completed,
        ]);
        $buyerToken = $buyer->createToken('mobile', ['mobile'])->plainTextToken;

        $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->deleteJson("/api/admin/users/{$seller->id}")
            ->assertOk();

        $this->withHeader('Authorization', "Bearer {$buyerToken}")
            ->getJson("/api/transactions/{$transaction->id}")
            ->assertOk()
            ->assertJsonPath('data.counterparty.id', $seller->id)
            ->assertJsonPath('data.counterparty.name', 'Historical Seller')
            ->assertJsonPath('data.counterparty.email', 'historical@example.com');
    }

    public function test_soft_deleted_email_remains_reserved_by_the_unique_constraint(): void
    {
        $deleted = User::factory()->create(['email' => 'reserved@example.com']);
        $replacement = User::factory()->create();

        $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->deleteJson("/api/admin/users/{$deleted->id}")
            ->assertOk();

        $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->putJson("/api/admin/users/{$replacement->id}", [
                'name' => $replacement->name,
                'email' => 'reserved@example.com',
            ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('email');
    }
}
