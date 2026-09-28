<?php

namespace Tests\Feature\Auth;

use App\Enums\SellerCapability;
use App\Enums\UserRole;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class MobileAuthTest extends TestCase
{
    use RefreshDatabase;

    /*
    |--------------------------------------------------------------------------
    | Registration
    |--------------------------------------------------------------------------
    */

    #[Test]
    public function a_guest_can_register_and_receive_a_bearer_token(): void
    {
        $response = $this->postJson('/api/auth/register', [
            'name' => 'Juan Dela Cruz',
            'email' => 'juan@agrobenta.test',
            'password' => 'secret-password',
            'password_confirmation' => 'secret-password',
        ]);

        $response->assertCreated()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.token_type', 'Bearer')
            ->assertJsonPath('data.user.name', 'Juan Dela Cruz')
            ->assertJsonPath('data.user.email', 'juan@agrobenta.test')
            ->assertJsonStructure([
                'success',
                'message',
                'data' => ['token', 'token_type', 'user'],
            ]);

        $user = User::query()->where('email', 'juan@agrobenta.test')->sole();

        $this->assertDatabaseHas('personal_access_tokens', [
            'tokenable_id' => $user->id,
            'name' => 'mobile',
        ]);
    }

    #[Test]
    public function registration_requires_name_email_and_password(): void
    {
        $this->postJson('/api/auth/register', [])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['name', 'email', 'password']);
    }

    #[Test]
    public function registration_requires_a_valid_email(): void
    {
        $this->postJson('/api/auth/register', [
            'name' => 'Juan Dela Cruz',
            'email' => 'not-an-email',
            'password' => 'secret-password',
            'password_confirmation' => 'secret-password',
        ])->assertUnprocessable()
            ->assertJsonValidationErrors(['email']);
    }

    #[Test]
    public function registration_requires_the_password_to_be_confirmed(): void
    {
        $this->postJson('/api/auth/register', [
            'name' => 'Juan Dela Cruz',
            'email' => 'juan@agrobenta.test',
            'password' => 'secret-password',
            'password_confirmation' => 'different-password',
        ])->assertUnprocessable()
            ->assertJsonValidationErrors(['password']);
    }

    #[Test]
    public function registration_enforces_a_minimum_password_length_of_eight(): void
    {
        $this->postJson('/api/auth/register', [
            'name' => 'Juan Dela Cruz',
            'email' => 'juan@agrobenta.test',
            'password' => 'short7c',
            'password_confirmation' => 'short7c',
        ])->assertUnprocessable()
            ->assertJsonValidationErrors(['password']);
    }

    #[Test]
    public function registration_rejects_a_duplicate_email(): void
    {
        User::factory()->create(['email' => 'juan@agrobenta.test']);

        $this->postJson('/api/auth/register', [
            'name' => 'Juan Dela Cruz',
            'email' => 'juan@agrobenta.test',
            'password' => 'secret-password',
            'password_confirmation' => 'secret-password',
        ])->assertUnprocessable()
            ->assertJsonValidationErrors(['email']);
    }

    #[Test]
    public function a_registration_request_cannot_set_role_or_seller_capability(): void
    {
        $response = $this->postJson('/api/auth/register', [
            'name' => 'Mallory',
            'email' => 'mallory@agrobenta.test',
            'password' => 'secret-password',
            'password_confirmation' => 'secret-password',
            'role' => UserRole::Admin->value,
            'seller_capability' => SellerCapability::Seller->value,
        ])->assertCreated();

        $response->assertJsonPath('data.user.role', UserRole::User->value)
            ->assertJsonPath('data.user.seller_capability', SellerCapability::Buyer->value);

        $this->assertDatabaseHas('users', [
            'email' => 'mallory@agrobenta.test',
            'role' => UserRole::User->value,
            'seller_capability' => SellerCapability::Buyer->value,
        ]);
    }

    /*
    |--------------------------------------------------------------------------
    | Login
    |--------------------------------------------------------------------------
    */

    #[Test]
    public function a_registered_user_can_log_in_and_receive_a_bearer_token(): void
    {
        User::factory()->create([
            'email' => 'juan@agrobenta.test',
            'password' => 'secret-password',
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $response = $this->postJson('/api/auth/login', [
            'email' => 'juan@agrobenta.test',
            'password' => 'secret-password',
        ]);

        $response->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.token_type', 'Bearer')
            ->assertJsonPath('data.user.email', 'juan@agrobenta.test')
            ->assertJsonMissingPath('data.user.password')
            ->assertJsonStructure([
                'success',
                'message',
                'data' => ['token', 'token_type', 'user'],
            ]);

        $user = User::query()->where('email', 'juan@agrobenta.test')->sole();

        $this->assertDatabaseHas('personal_access_tokens', [
            'tokenable_id' => $user->id,
            'name' => 'mobile',
        ]);
    }

    #[Test]
    public function login_requires_email_and_password(): void
    {
        $this->postJson('/api/auth/login', [])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['email', 'password']);
    }

    #[Test]
    public function login_fails_generically_for_invalid_credentials(): void
    {
        User::factory()->create([
            'email' => 'juan@agrobenta.test',
            'password' => 'correct-password',
        ]);

        $wrongPassword = $this->postJson('/api/auth/login', [
            'email' => 'juan@agrobenta.test',
            'password' => 'wrong-password',
        ])->assertUnauthorized();

        $unknownUser = $this->postJson('/api/auth/login', [
            'email' => 'ghost@agrobenta.test',
            'password' => 'whatever',
        ])->assertUnauthorized();

        // The two failures must be indistinguishable, so neither can be used
        // to enumerate which accounts exist.
        $this->assertSame(
            $wrongPassword->json('message'),
            $unknownUser->json('message'),
        );
    }

    #[Test]
    public function an_admin_account_cannot_log_in_through_the_mobile_flow(): void
    {
        User::factory()->admin()->create([
            'email' => 'admin@agrobenta.test',
            'password' => 'secret-password',
        ]);

        $this->postJson('/api/auth/login', [
            'email' => 'admin@agrobenta.test',
            'password' => 'secret-password',
        ])->assertForbidden();

        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    /*
    |--------------------------------------------------------------------------
    | Me
    |--------------------------------------------------------------------------
    */

    #[Test]
    public function an_authenticated_mobile_user_can_fetch_their_profile(): void
    {
        $user = User::factory()->create(['email' => 'juan@agrobenta.test']);

        $token = $user->createToken('mobile', ['mobile'])->plainTextToken;

        $this->getJson('/api/auth/me', [
            'Authorization' => "Bearer {$token}",
        ])->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.id', $user->id)
            ->assertJsonPath('data.email', 'juan@agrobenta.test')
            ->assertJsonPath('data.role', UserRole::User->value)
            ->assertJsonPath('data.seller_capability', SellerCapability::Buyer->value);
    }

    #[Test]
    public function a_guest_cannot_fetch_a_profile(): void
    {
        $this->getJson('/api/auth/me')->assertUnauthorized();
    }

    #[Test]
    public function a_token_without_the_mobile_ability_cannot_fetch_a_profile(): void
    {
        $user = User::factory()->create();

        // Explicitly empty: `createToken()` defaults to `['*']`, which would
        // otherwise mint a full-access token and make this assertion vacuous.
        $token = $user->createToken('user_token', [])->plainTextToken;

        $this->getJson('/api/auth/me', [
            'Authorization' => "Bearer {$token}",
        ])->assertForbidden();
    }

    #[Test]
    public function the_profile_exposes_no_sensitive_fields(): void
    {
        $user = User::factory()->create(['email' => 'juan@agrobenta.test']);

        $token = $user->createToken('mobile', ['mobile'])->plainTextToken;

        $response = $this->getJson('/api/auth/me', [
            'Authorization' => "Bearer {$token}",
        ])->assertOk()
            ->assertJsonMissingPath('data.password')
            ->assertJsonMissingPath('data.remember_token')
            ->assertJsonMissingPath('data.tokens')
            ->assertJsonStructure([
                'success',
                'data' => [
                    'id', 'name', 'email', 'role',
                    'seller_capability', 'email_verified_at',
                    'created_at', 'updated_at',
                ],
            ]);

        $this->assertStringNotContainsString('secret-password', $response->getContent());
        $this->assertStringNotContainsString(
            (string) $user->password,
            $response->getContent(),
        );
    }

    /*
    |--------------------------------------------------------------------------
    | Logout
    |--------------------------------------------------------------------------
    */

    #[Test]
    public function logging_out_revokes_the_mobile_bearer_token(): void
    {
        $user = User::factory()->create([
            'email' => 'juan@agrobenta.test',
            'password' => 'secret-password',
        ]);

        $login = $this->postJson('/api/auth/login', [
            'email' => 'juan@agrobenta.test',
            'password' => 'secret-password',
        ])->assertOk();

        $token = $login->json('data.token');

        $this->postJson('/api/auth/logout', [], [
            'Authorization' => "Bearer {$token}",
        ])->assertOk()
            ->assertJsonPath('success', true);

        $this->assertDatabaseCount('personal_access_tokens', 0);

        app('auth')->forgetGuards();

        $this->getJson('/api/auth/me', [
            'Authorization' => "Bearer {$token}",
        ])->assertUnauthorized();
    }

    #[Test]
    public function a_guest_cannot_log_out(): void
    {
        $this->postJson('/api/auth/logout')->assertUnauthorized();
    }

    #[Test]
    public function unauthenticated_api_requests_stay_on_the_401_path(): void
    {
        // Regression guard: with no `login` route, a request that does not
        // advertise JSON used to fall through to a guest redirect and surface
        // a 500. `ForceJsonResponse` keeps it a 401.
        $this->get('/api/auth/me')->assertUnauthorized();
        $this->post('/api/auth/logout')->assertUnauthorized();

        // Pre-existing admin routes are covered by the same middleware.
        $this->get('/api/admin/dashboard')->assertUnauthorized();
    }

    #[Test]
    public function logging_out_does_not_revoke_the_users_other_tokens(): void
    {
        $user = User::factory()->create();

        $current = $user->createToken('mobile', ['mobile'])->plainTextToken;
        $other = $user->createToken('mobile', ['mobile'])->plainTextToken;

        $this->postJson('/api/auth/logout', [], [
            'Authorization' => "Bearer {$current}",
        ])->assertOk();

        $this->assertDatabaseCount('personal_access_tokens', 1);

        app('auth')->forgetGuards();

        $this->getJson('/api/auth/me', [
            'Authorization' => "Bearer {$other}",
        ])->assertOk()
            ->assertJsonPath('data.id', $user->id);
    }

    /*
    |--------------------------------------------------------------------------
    | Token separation and cross-context access
    |--------------------------------------------------------------------------
    */

    #[Test]
    public function the_mobile_token_carries_the_mobile_ability_and_not_admin(): void
    {
        $user = User::factory()->create([
            'email' => 'juan@agrobenta.test',
            'password' => 'secret-password',
        ]);

        $login = $this->postJson('/api/auth/login', [
            'email' => 'juan@agrobenta.test',
            'password' => 'secret-password',
        ])->assertOk();

        // The plain text form only exists on the login response; a token model
        // re-read from the database has no `plainTextToken`.
        $token = $login->json('data.token');

        $accessToken = $user->tokens()->firstOrFail();

        $this->assertTrue($accessToken->can('mobile'));
        $this->assertFalse($accessToken->can('admin'));

        // Admin rejection is therefore a property of the account, not an
        // artefact of an admin-shaped token.
        $this->getJson('/api/admin/dashboard', [
            'Authorization' => "Bearer {$token}",
        ])->assertForbidden();
    }

    #[Test]
    public function an_admin_token_cannot_be_used_on_mobile_endpoints(): void
    {
        $admin = User::factory()->admin()->create();

        $token = $admin->createToken('admin_token', ['admin'])->plainTextToken;

        $this->getJson('/api/auth/me', [
            'Authorization' => "Bearer {$token}",
        ])->assertForbidden();

        $this->postJson('/api/auth/logout', [], [
            'Authorization' => "Bearer {$token}",
        ])->assertForbidden();
    }

    #[Test]
    public function a_mobile_token_cannot_be_used_on_admin_endpoints(): void
    {
        $user = User::factory()->create();

        $token = $user->createToken('mobile', ['mobile'])->plainTextToken;

        $this->getJson('/api/admin/auth/me', [
            'Authorization' => "Bearer {$token}",
        ])->assertForbidden();

        $this->getJson('/api/admin/users', [
            'Authorization' => "Bearer {$token}",
        ])->assertForbidden();
    }

    #[Test]
    public function the_registration_response_never_leaks_the_password(): void
    {
        $response = $this->postJson('/api/auth/register', [
            'name' => 'Juan Dela Cruz',
            'email' => 'juan@agrobenta.test',
            'password' => 'secret-password',
            'password_confirmation' => 'secret-password',
        ])->assertCreated()
            ->assertJsonMissingPath('data.user.password');

        $user = User::query()->where('email', 'juan@agrobenta.test')->sole();

        $this->assertStringNotContainsString('secret-password', $response->getContent());
        $this->assertStringNotContainsString((string) $user->password, $response->getContent());

        // Stored hashed, never in plain text.
        $this->assertNotSame('secret-password', $user->password);
    }
}
