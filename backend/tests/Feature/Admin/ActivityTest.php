<?php

namespace Tests\Feature\Admin;

use App\Enums\SellerCapability;
use App\Enums\UserRole;
use App\Models\Activity;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ActivityTest extends TestCase
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

    private function adminToken(): string
    {
        return $this->admin->createToken('admin_token', ['admin'])->plainTextToken;
    }

    public function test_guest_cannot_access_activities(): void
    {
        $response = $this->getJson('/api/admin/activities');

        $response->assertStatus(401);
    }

    public function test_regular_user_cannot_access_activities(): void
    {
        $user = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $token = $user->createToken('user_token')->plainTextToken;

        $response = $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/admin/activities');

        $response->assertStatus(403);
    }

    public function test_admin_can_access_activities(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/activities');

        $response->assertStatus(200);
        $response->assertJsonStructure([
            'success',
            'data' => [
                'activities' => [],
                'pagination' => [
                    'current_page',
                    'last_page',
                    'per_page',
                    'total',
                ],
            ],
        ]);
    }

    public function test_activities_are_returned(): void
    {
        $user = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        Activity::create([
            'user_id' => $user->id,
            'action' => 'listing_created',
            'description' => 'Created a new livestock listing',
        ]);

        Activity::create([
            'user_id' => $user->id,
            'action' => 'transaction_completed',
            'description' => 'Transaction was completed',
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/activities');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(2, $data['pagination']['total']);
        $this->assertCount(2, $data['activities']);
    }

    public function test_newest_activities_are_first(): void
    {
        $user = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $first = Activity::create([
            'user_id' => $user->id,
            'action' => 'old_action',
            'description' => 'Old activity',
            'created_at' => now()->subDays(5),
        ]);

        $second = Activity::create([
            'user_id' => $user->id,
            'action' => 'new_action',
            'description' => 'New activity',
            'created_at' => now()->subDay(),
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/activities');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals($second->id, $data['activities'][0]['id']);
        $this->assertEquals($first->id, $data['activities'][1]['id']);
    }

    public function test_search_works(): void
    {
        $user = User::factory()->create([
            'name' => 'Juan Dela Cruz',
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        Activity::create([
            'user_id' => $user->id,
            'action' => 'listing_created',
            'description' => 'Created a new listing',
        ]);

        Activity::create([
            'user_id' => $user->id,
            'action' => 'profile_updated',
            'description' => 'Updated profile',
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/activities?search=listing');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(1, $data['pagination']['total']);
    }

    public function test_search_by_user_name(): void
    {
        $user1 = User::factory()->create([
            'name' => 'Juan Dela Cruz',
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $user2 = User::factory()->create([
            'name' => 'Maria Santos',
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        Activity::create([
            'user_id' => $user1->id,
            'action' => 'listing_created',
            'description' => 'Juan created a listing',
        ]);

        Activity::create([
            'user_id' => $user2->id,
            'action' => 'listing_created',
            'description' => 'Maria created a listing',
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/activities?search=Juan');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(1, $data['pagination']['total']);
    }

    public function test_action_filter_works(): void
    {
        $user = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        Activity::create([
            'user_id' => $user->id,
            'action' => 'listing_created',
            'description' => 'Created a listing',
        ]);

        Activity::create([
            'user_id' => $user->id,
            'action' => 'profile_updated',
            'description' => 'Updated profile',
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/activities?action=listing_created');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(1, $data['pagination']['total']);
        $this->assertEquals('listing_created', $data['activities'][0]['action']);
    }

    public function test_date_filtering_works(): void
    {
        $user = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        Activity::factory()->createdAt(now()->subDays(10))->create([
            'user_id' => $user->id,
            'action' => 'old_action',
            'description' => 'Old activity',
        ]);

        Activity::factory()->createdAt(now()->subDays(2))->create([
            'user_id' => $user->id,
            'action' => 'new_action',
            'description' => 'New activity',
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/activities?date_from='.now()->subDays(5)->format('Y-m-d'));

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertEquals(1, $data['pagination']['total']);
        $this->assertEquals('new_action', $data['activities'][0]['action']);
    }

    public function test_pagination_works(): void
    {
        $user = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        for ($i = 0; $i < 24; $i++) {
            Activity::factory()->create([
                'user_id' => $user->id,
                'action' => 'test_action',
                'description' => "Activity {$i}",
            ]);
        }

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/activities?per_page=10&page=1');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertCount(10, $data['activities']);
        $this->assertEquals(1, $data['pagination']['current_page']);
        $this->assertEquals(3, $data['pagination']['last_page']);
        $this->assertEquals(24, $data['pagination']['total']);
    }

    public function test_empty_state_works(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/activities');

        $response->assertStatus(200);

        $data = $response->json('data');
        $this->assertCount(0, $data['activities']);
        $this->assertEquals(0, $data['pagination']['total']);
    }

    public function test_sensitive_fields_are_not_exposed(): void
    {
        $user = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        Activity::create([
            'user_id' => $user->id,
            'action' => 'test_action',
            'description' => 'Test activity',
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/activities');

        $response->assertStatus(200);

        $activities = $response->json('data.activities');
        $this->assertNotEmpty($activities);

        foreach ($activities as $activity) {
            $this->assertArrayNotHasKey('user_id', $activity);

            if ($activity['user'] !== null) {
                $this->assertArrayNotHasKey('password', $activity['user']);
                $this->assertArrayNotHasKey('remember_token', $activity['user']);
            }
        }
    }

    public function test_guest_cannot_access_activity_summary(): void
    {
        $response = $this->getJson('/api/admin/activities/summary');

        $response->assertStatus(401);
    }

    public function test_regular_user_cannot_access_activity_summary(): void
    {
        $user = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $token = $user->createToken('user_token')->plainTextToken;

        $response = $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/admin/activities/summary');

        $response->assertStatus(403);
    }

    public function test_admin_can_access_activity_summary(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/activities/summary');

        $response->assertStatus(200);
        $response->assertJsonStructure([
            'success',
            'data' => [
                'total_activities',
                'active_actors',
                'moderation_actions',
                'configuration_changes',
                'window',
                'since',
                'until',
            ],
        ]);
    }

    public function test_activity_summary_counts_last_24_hours(): void
    {
        $user = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        Activity::factory()->create([
            'user_id' => $user->id,
            'action' => 'listing_approved',
            'created_at' => now()->subHours(2),
        ]);

        Activity::factory()->create([
            'user_id' => $user->id,
            'action' => 'settings_updated',
            'created_at' => now()->subHours(3),
        ]);

        Activity::factory()->create([
            'user_id' => $user->id,
            'action' => 'listing_rejected',
            'created_at' => now()->subHours(1),
        ]);

        Activity::factory()->create([
            'user_id' => $user->id,
            'action' => 'old_action',
            'created_at' => now()->subDays(2),
        ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/activities/summary');

        $response->assertStatus(200);
        $data = $response->json('data');
        $this->assertEquals(3, $data['total_activities']);
        $this->assertEquals(1, $data['active_actors']);
        $this->assertEquals(2, $data['moderation_actions']);
        $this->assertEquals(1, $data['configuration_changes']);
        $this->assertEquals('last_24h', $data['window']);
    }

    public function test_activity_summary_moderation_includes_all_types(): void
    {
        $user = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        Activity::factory()->create(['user_id' => $user->id, 'action' => 'listing_approved', 'created_at' => now()->subHours(1)]);
        Activity::factory()->create(['user_id' => $user->id, 'action' => 'listing_rejected', 'created_at' => now()->subHours(1)]);
        Activity::factory()->create(['user_id' => $user->id, 'action' => 'listing_deactivated', 'created_at' => now()->subHours(1)]);
        Activity::factory()->create(['user_id' => $user->id, 'action' => 'seller_verification_approved', 'created_at' => now()->subHours(1)]);
        Activity::factory()->create(['user_id' => $user->id, 'action' => 'seller_verification_rejected', 'created_at' => now()->subHours(1)]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/activities/summary');

        $response->assertStatus(200);
        $this->assertEquals(5, $response->json('data.moderation_actions'));
    }

    public function test_activity_summary_active_actors_distinct(): void
    {
        $user1 = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);
        $user2 = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        Activity::factory()->create(['user_id' => $user1->id, 'action' => 'listing_created', 'created_at' => now()->subHours(1)]);
        Activity::factory()->create(['user_id' => $user1->id, 'action' => 'listing_updated', 'created_at' => now()->subHours(2)]);
        Activity::factory()->create(['user_id' => $user2->id, 'action' => 'profile_updated', 'created_at' => now()->subHours(3)]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/activities/summary');

        $response->assertStatus(200);
        $this->assertEquals(2, $response->json('data.active_actors'));
    }

    public function test_activities_can_filter_by_multiple_actions(): void
    {
        $user = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        Activity::factory()->create(['user_id' => $user->id, 'action' => 'listing_approved']);
        Activity::factory()->create(['user_id' => $user->id, 'action' => 'listing_rejected']);
        Activity::factory()->create(['user_id' => $user->id, 'action' => 'profile_updated']);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/activities?actions[]=listing_approved&actions[]=listing_rejected');

        $response->assertStatus(200);
        $data = $response->json('data');
        $this->assertEquals(2, $data['pagination']['total']);
    }
}
