<?php

namespace Tests\Feature\Auth;

use App\Enums\SellerCapability;
use App\Enums\UserRole;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class GoogleSignInTest extends TestCase
{
    use RefreshDatabase;

    private const CLIENT_ID = 'test-web-client.apps.googleusercontent.com';

    protected function setUp(): void
    {
        parent::setUp();

        config(['services.google.client_id' => self::CLIENT_ID]);
    }

    /**
     * Fake Google's tokeninfo reply, starting from a valid token's claims.
     *
     * @param  array<string, mixed>  $overrides
     */
    private function fakeTokenInfo(array $overrides = [], int $status = 200): void
    {
        Http::fake([
            'oauth2.googleapis.com/tokeninfo*' => Http::response([
                'iss' => 'https://accounts.google.com',
                'aud' => self::CLIENT_ID,
                'sub' => '1234567890',
                'email' => 'juan@gmail.com',
                'email_verified' => 'true',
                'name' => 'Juan Dela Cruz',
                'exp' => (string) (time() + 3600),
                ...$overrides,
            ], $status),
        ]);
    }

    #[Test]
    public function a_new_google_user_gets_a_normal_buyer_account_and_a_mobile_token(): void
    {
        $this->fakeTokenInfo();

        $response = $this->postJson('/api/auth/google', ['id_token' => 'valid-token']);

        $response->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.token_type', 'Bearer')
            ->assertJsonPath('data.user.email', 'juan@gmail.com')
            ->assertJsonPath('data.user.name', 'Juan Dela Cruz')
            ->assertJsonMissingPath('data.user.password');

        $user = User::query()->where('email', 'juan@gmail.com')->sole();

        $this->assertSame(UserRole::User, $user->role);
        $this->assertSame(SellerCapability::Buyer, $user->seller_capability);
        $this->assertDatabaseHas('personal_access_tokens', [
            'tokenable_id' => $user->id,
            'name' => 'mobile',
        ]);

        Http::assertSent(fn ($request) => $request['id_token'] === 'valid-token');
    }

    #[Test]
    public function an_existing_account_with_the_same_email_is_signed_in_not_duplicated(): void
    {
        $existing = User::factory()->create([
            'email' => 'juan@gmail.com',
            'name' => 'Existing Name',
        ]);
        $this->fakeTokenInfo();

        $this->postJson('/api/auth/google', ['id_token' => 'valid-token'])
            ->assertOk()
            ->assertJsonPath('data.user.id', $existing->id)
            ->assertJsonPath('data.user.name', 'Existing Name');

        $this->assertSame(1, User::query()->where('email', 'juan@gmail.com')->count());
    }

    #[Test]
    public function an_administrator_cannot_sign_in_to_mobile_with_google(): void
    {
        User::factory()->admin()->create(['email' => 'juan@gmail.com']);
        $this->fakeTokenInfo();

        $this->postJson('/api/auth/google', ['id_token' => 'valid-token'])
            ->assertForbidden();

        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    #[Test]
    public function a_token_rejected_by_google_is_refused(): void
    {
        $this->fakeTokenInfo(['error' => 'invalid_token'], 400);

        $this->postJson('/api/auth/google', ['id_token' => 'bad-token'])
            ->assertUnauthorized();

        $this->assertDatabaseCount('users', 0);
    }

    #[Test]
    public function a_token_for_another_app_is_refused(): void
    {
        $this->fakeTokenInfo(['aud' => 'someone-else.apps.googleusercontent.com']);

        $this->postJson('/api/auth/google', ['id_token' => 'valid-token'])
            ->assertUnauthorized();

        $this->assertDatabaseCount('users', 0);
    }

    #[Test]
    public function a_token_with_an_unverified_email_is_refused(): void
    {
        $this->fakeTokenInfo(['email_verified' => 'false']);

        $this->postJson('/api/auth/google', ['id_token' => 'valid-token'])
            ->assertUnauthorized();
    }

    #[Test]
    public function a_token_from_another_issuer_is_refused(): void
    {
        $this->fakeTokenInfo(['iss' => 'https://evil.example.com']);

        $this->postJson('/api/auth/google', ['id_token' => 'valid-token'])
            ->assertUnauthorized();
    }

    #[Test]
    public function an_expired_token_is_refused(): void
    {
        $this->fakeTokenInfo(['exp' => (string) (time() - 10)]);

        $this->postJson('/api/auth/google', ['id_token' => 'valid-token'])
            ->assertUnauthorized();
    }

    #[Test]
    public function sign_in_is_refused_when_the_client_id_is_not_configured(): void
    {
        config(['services.google.client_id' => null]);
        $this->fakeTokenInfo();

        $this->postJson('/api/auth/google', ['id_token' => 'valid-token'])
            ->assertUnauthorized();

        Http::assertNothingSent();
    }

    #[Test]
    public function the_id_token_is_required(): void
    {
        $this->postJson('/api/auth/google', [])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['id_token']);
    }

    #[Test]
    public function the_google_token_only_carries_the_mobile_ability(): void
    {
        $this->fakeTokenInfo();

        $token = $this->postJson('/api/auth/google', ['id_token' => 'valid-token'])
            ->json('data.token');

        $this->getJson('/api/admin/auth/me', [
            'Authorization' => "Bearer {$token}",
        ])->assertForbidden();
    }
}
