<?php

namespace Tests\Feature\Admin;

use App\Enums\SellerCapability;
use App\Enums\UserRole;
use App\Models\Setting;
use App\Models\User;
use Illuminate\Contracts\Auth\Factory;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class SettingsTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    private User $buyer;

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

        $this->seedSettings();
    }

    private function adminToken(): string
    {
        return $this->admin->createToken('admin_token', ['admin'])->plainTextToken;
    }

    private function seedSettings(): void
    {
        $settings = [
            ['key' => 'system.name', 'value' => 'AgroBenta', 'group' => 'system', 'label' => 'System Name', 'description' => 'Platform name.'],
            ['key' => 'system.description', 'value' => 'A livestock trading platform.', 'group' => 'system', 'label' => 'System Description', 'description' => 'Platform description.'],
            ['key' => 'admin_contact.name', 'value' => 'Administrator', 'group' => 'admin_contact', 'label' => 'Contact Name', 'description' => 'Contact name.'],
            ['key' => 'admin_contact.email', 'value' => 'admin@example.com', 'group' => 'admin_contact', 'label' => 'Contact Email', 'description' => 'Contact email.'],
            ['key' => 'admin_contact.phone', 'value' => '', 'group' => 'admin_contact', 'label' => 'Contact Phone', 'description' => 'Contact phone.'],
        ];

        foreach ($settings as $setting) {
            Setting::create($setting);
        }
    }

    // ── GET /api/admin/settings ─────────────────────────────────────────

    public function test_guest_cannot_access_settings(): void
    {
        $response = $this->getJson('/api/admin/settings');

        $response->assertStatus(401);
    }

    public function test_regular_user_cannot_access_settings(): void
    {
        $token = $this->buyer->createToken('user_token')->plainTextToken;

        $response = $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/admin/settings');

        $response->assertStatus(403);
    }

    public function test_admin_can_get_settings(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/settings');

        $response->assertStatus(200);
        $response->assertJsonStructure([
            'success',
            'data' => [
                'system' => [
                    ['key', 'value', 'group', 'label', 'description'],
                ],
                'admin_contact' => [
                    ['key', 'value', 'group', 'label', 'description'],
                ],
            ],
        ]);
    }

    public function test_settings_returns_seeded_values(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/settings');

        $response->assertStatus(200);

        $systemSettings = $response->json('data.system');
        $this->assertCount(2, $systemSettings);

        $nameSetting = collect($systemSettings)->firstWhere('key', 'system.name');
        $this->assertNotNull($nameSetting);
        $this->assertEquals('AgroBenta', $nameSetting['value']);

        $contactSettings = $response->json('data.admin_contact');
        $this->assertCount(3, $contactSettings);
    }

    public function test_settings_groups_are_sorted(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/settings');

        $response->assertStatus(200);

        $groups = array_keys($response->json('data'));
        $this->assertEquals(['admin_contact', 'system'], $groups);
    }

    // ── PUT /api/admin/settings ─────────────────────────────────────────

    public function test_guest_cannot_update_settings(): void
    {
        $response = $this->putJson('/api/admin/settings', [
            'system.name' => 'New Name',
        ]);

        $response->assertStatus(401);
    }

    public function test_regular_user_cannot_update_settings(): void
    {
        $token = $this->buyer->createToken('user_token')->plainTextToken;

        $response = $this->withHeader('Authorization', "Bearer {$token}")
            ->putJson('/api/admin/settings', [
                'system.name' => 'New Name',
            ]);

        $response->assertStatus(403);
    }

    public function test_admin_can_update_allowed_settings(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->putJson('/api/admin/settings', [
                'system.name' => 'New AgroBenta',
                'admin_contact.email' => 'new@example.com',
            ]);

        $response->assertStatus(200);
        $response->assertJson([
            'success' => true,
            'message' => 'Settings updated.',
        ]);
        $response->assertJsonStructure([
            'updated',
            'rejected',
            'data',
        ]);

        $this->assertContains('system.name', $response->json('updated'));
        $this->assertContains('admin_contact.email', $response->json('updated'));
        $this->assertEmpty($response->json('rejected'));

        $this->assertDatabaseHas('settings', ['key' => 'system.name', 'value' => 'New AgroBenta']);
        $this->assertDatabaseHas('settings', ['key' => 'admin_contact.email', 'value' => 'new@example.com']);
    }

    public function test_non_allowed_keys_are_rejected(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->putJson('/api/admin/settings', [
                'system.name' => 'Valid Update',
                'arbitrary.key' => 'Should be rejected',
                'another.bad.key' => 'Also rejected',
            ]);

        $response->assertStatus(200);

        $this->assertContains('system.name', $response->json('updated'));
        $this->assertContains('arbitrary.key', $response->json('rejected'));
        $this->assertContains('another.bad.key', $response->json('rejected'));

        $this->assertDatabaseHas('settings', ['key' => 'system.name', 'value' => 'Valid Update']);
        $this->assertDatabaseMissing('settings', ['key' => 'arbitrary.key']);
    }

    public function test_empty_payload_returns_empty_results(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->putJson('/api/admin/settings', []);

        $response->assertStatus(200);
        $this->assertEmpty($response->json('updated'));
        $this->assertEmpty($response->json('rejected'));
    }

    public function test_invalid_email_is_rejected(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->putJson('/api/admin/settings', [
                'admin_contact.email' => 'not-an-email',
            ]);

        $response->assertStatus(422);
        $response->assertJsonValidationErrors(['admin_contact.email']);
    }

    public function test_system_name_max_length(): void
    {
        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->putJson('/api/admin/settings', [
                'system.name' => str_repeat('a', 256),
            ]);

        $response->assertStatus(422);
        $response->assertJsonValidationErrors(['system.name']);
    }

    public function test_settings_reflect_after_update(): void
    {
        $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->putJson('/api/admin/settings', [
                'system.name' => 'Updated Name',
            ]);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/settings');

        $response->assertStatus(200);

        $systemSettings = $response->json('data.system');
        $nameSetting = collect($systemSettings)->firstWhere('key', 'system.name');
        $this->assertEquals('Updated Name', $nameSetting['value']);
    }

    public function test_authorization_remains_enforced(): void
    {
        $response = $this->getJson('/api/admin/settings');
        $response->assertStatus(401);

        $token = $this->buyer->createToken('user_token')->plainTextToken;
        $response = $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/admin/settings');
        $response->assertStatus(403);

        app(Factory::class)->forgetGuards();

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/settings');
        $response->assertStatus(200);
    }
}
