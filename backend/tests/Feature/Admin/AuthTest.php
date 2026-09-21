<?php

namespace Tests\Feature\Admin;

use App\Enums\SellerCapability;
use App\Enums\UserRole;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class AuthTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function an_admin_can_log_in_and_receive_a_bearer_token(): void
    {
        $admin = User::factory()->admin()->create([
            'email' => 'admin@agrobenta.test',
            'password' => 'secret-password',
        ]);

        $response = $this->postJson('/api/admin/auth/login', [
            'email' => 'admin@agrobenta.test',
            'password' => 'secret-password',
        ]);

        $response->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.token_type', 'Bearer')
            ->assertJsonPath('data.user.id', $admin->id)
            ->assertJsonPath('data.user.email', 'admin@agrobenta.test')
            ->assertJsonPath('data.user.role', UserRole::Admin->value)
            ->assertJsonMissingPath('data.user.password')
            ->assertJsonStructure([
                'success',
                'message',
                'data' => ['token', 'token_type', 'user'],
            ]);

        $this->assertDatabaseHas('personal_access_tokens', [
            'tokenable_id' => $admin->id,
            'name' => 'admin_token',
        ]);
    }

    #[Test]
    public function login_rejects_invalid_credentials(): void
    {
        User::factory()->admin()->create([
            'email' => 'admin@agrobenta.test',
            'password' => 'correct-password',
        ]);

        $this->postJson('/api/admin/auth/login', [
            'email' => 'admin@agrobenta.test',
            'password' => 'wrong-password',
        ])->assertUnauthorized();

        $this->postJson('/api/admin/auth/login', [
            'email' => 'ghost@agrobenta.test',
            'password' => 'whatever',
        ])->assertUnauthorized();
    }

    #[Test]
    public function login_requires_email_and_password(): void
    {
        $this->postJson('/api/admin/auth/login', [])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['email', 'password']);
    }

    #[Test]
    public function a_regular_user_cannot_log_in_as_an_admin(): void
    {
        User::factory()->create([
            'email' => 'user@agrobenta.test',
            'password' => 'secret-password',
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $this->postJson('/api/admin/auth/login', [
            'email' => 'user@agrobenta.test',
            'password' => 'secret-password',
        ])->assertUnauthorized();
    }

    #[Test]
    public function a_guest_cannot_access_protected_admin_endpoints(): void
    {
        $this->postJson('/api/admin/auth/logout')->assertUnauthorized();
        $this->getJson('/api/admin/auth/me')->assertUnauthorized();
    }

    #[Test]
    public function an_admin_can_fetch_their_profile(): void
    {
        $admin = User::factory()->admin()->create([
            'email' => 'admin@agrobenta.test',
        ]);

        $token = $admin->createToken('admin_token', ['admin'])->plainTextToken;

        $this->getJson('/api/admin/auth/me', [
            'Authorization' => "Bearer {$token}",
        ])->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.id', $admin->id)
            ->assertJsonPath('data.email', 'admin@agrobenta.test')
            ->assertJsonPath('data.role', UserRole::Admin->value)
            ->assertJsonPath('data.seller_capability', SellerCapability::Buyer->value);
    }

    #[Test]
    public function a_non_admin_cannot_access_protected_admin_endpoints(): void
    {
        $user = User::factory()->create();

        $token = $user->createToken('user_token')->plainTextToken;

        $this->getJson('/api/admin/auth/me', [
            'Authorization' => "Bearer {$token}",
        ])->assertForbidden();

        $this->postJson('/api/admin/auth/logout', [], [
            'Authorization' => "Bearer {$token}",
        ])->assertForbidden();
    }

    #[Test]
    public function logging_out_revokes_the_bearer_token(): void
    {
        $admin = User::factory()->admin()->create([
            'email' => 'admin@agrobenta.test',
            'password' => 'secret-password',
        ]);

        $login = $this->postJson('/api/admin/auth/login', [
            'email' => 'admin@agrobenta.test',
            'password' => 'secret-password',
        ])->assertOk();

        $token = $login->json('data.token');

        $this->postJson('/api/admin/auth/logout', [], [
            'Authorization' => "Bearer {$token}",
        ])->assertOk()
            ->assertJsonPath('success', true);

        $this->assertDatabaseCount('personal_access_tokens', 0);

        app('auth')->forgetGuards();

        $this->getJson('/api/admin/auth/me', [
            'Authorization' => "Bearer {$token}",
        ])->assertUnauthorized();
    }

    #[Test]
    public function there_is_no_admin_registration_endpoint(): void
    {
        $this->postJson('/api/admin/auth/register', [
            'name' => 'Admin',
            'email' => 'admin@agrobenta.test',
            'password' => 'secret-password',
        ])->assertNotFound();
    }

    #[Test]
    public function the_scaffold_user_route_remains_functional(): void
    {
        $this->getJson('/api/user')->assertUnauthorized();

        $admin = User::factory()->admin()->create();

        $token = $admin->createToken('admin_token', ['admin'])->plainTextToken;

        $this->getJson('/api/user', [
            'Authorization' => "Bearer {$token}",
        ])->assertOk()
            ->assertJsonPath('email', $admin->email);
    }
}
