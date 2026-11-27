<?php

namespace Tests\Feature\Realtime;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Browser access to the Reverb private-channel authorization endpoint.
 *
 * The Admin Web (http://localhost:5174) and Flutter Web (http://localhost:8080)
 * call `/broadcasting/auth` cross-origin. If the CORS layer does not answer
 * that endpoint, the browser blocks the request after the preflight and no
 * private channel is ever subscribed. These tests pin the CORS headers and
 * confirm CORS does not loosen the channel authorization itself.
 */
class BroadcastingCorsTest extends TestCase
{
    use RefreshDatabase;

    private const ADMIN_WEB_ORIGIN = 'http://localhost:5174';

    private const FLUTTER_WEB_ORIGIN = 'http://localhost:8080';

    /**
     * Same local-HMAC Reverb setup as the other channel-auth tests: no network
     * is involved, and the channel callbacks are re-registered on the now
     * active `reverb` broadcaster.
     */
    private function configureReverbForAuthTests(): void
    {
        config()->set('broadcasting.default', 'reverb');
        config()->set('broadcasting.connections.reverb.key', 'test-key');
        config()->set('broadcasting.connections.reverb.secret', 'test-secret');
        config()->set('broadcasting.connections.reverb.app_id', 'test-app');
        config()->set('broadcasting.connections.reverb.options', [
            'host' => 'reverb',
            'port' => 8080,
            'scheme' => 'http',
            'useTLS' => false,
        ]);

        require base_path('routes/channels.php');
    }

    private function preflight(string $origin): TestResponse
    {
        return $this->call('OPTIONS', '/broadcasting/auth', [], [], [], [
            'HTTP_ORIGIN' => $origin,
            'HTTP_ACCESS_CONTROL_REQUEST_METHOD' => 'POST',
            'HTTP_ACCESS_CONTROL_REQUEST_HEADERS' => 'authorization,content-type',
        ]);
    }

    private function authorize(User $user, string $channelName, array $abilities, string $origin): TestResponse
    {
        $token = $user->createToken('test', $abilities)->plainTextToken;

        return $this->withHeaders([
            'Authorization' => 'Bearer '.$token,
            'Origin' => $origin,
        ])->postJson('/broadcasting/auth', [
            'channel_name' => $channelName,
            'socket_id' => '1234.5678',
        ]);
    }

    #[Test]
    public function the_admin_web_preflight_is_allowed(): void
    {
        $this->preflight(self::ADMIN_WEB_ORIGIN)
            ->assertNoContent()
            ->assertHeader('Access-Control-Allow-Origin', self::ADMIN_WEB_ORIGIN)
            ->assertHeader('Access-Control-Allow-Headers', 'authorization,content-type');
    }

    #[Test]
    public function the_flutter_web_preflight_is_allowed(): void
    {
        $this->preflight(self::FLUTTER_WEB_ORIGIN)
            ->assertNoContent()
            ->assertHeader('Access-Control-Allow-Origin', self::FLUTTER_WEB_ORIGIN);
    }

    #[Test]
    public function an_unlisted_origin_is_not_allowed(): void
    {
        $this->preflight('https://attacker.example')
            ->assertHeaderMissing('Access-Control-Allow-Origin');
    }

    #[Test]
    public function a_browser_can_authorize_its_own_user_channel(): void
    {
        $this->configureReverbForAuthTests();
        $user = User::factory()->create();

        $this->authorize($user, 'private-user.'.$user->id, ['mobile'], self::FLUTTER_WEB_ORIGIN)
            ->assertOk()
            ->assertJsonStructure(['auth'])
            ->assertHeader('Access-Control-Allow-Origin', self::FLUTTER_WEB_ORIGIN);
    }

    #[Test]
    public function a_browser_admin_can_authorize_the_shared_admin_channel(): void
    {
        $this->configureReverbForAuthTests();
        $admin = User::factory()->admin()->create();

        $this->authorize($admin, 'private-admin', ['admin'], self::ADMIN_WEB_ORIGIN)
            ->assertOk()
            ->assertJsonStructure(['auth'])
            ->assertHeader('Access-Control-Allow-Origin', self::ADMIN_WEB_ORIGIN);
    }

    #[Test]
    public function cors_does_not_let_a_browser_subscribe_to_another_users_channel(): void
    {
        $this->configureReverbForAuthTests();
        $user = User::factory()->create();
        $other = User::factory()->create();

        // Readable by the browser (CORS header present), but still refused.
        $this->authorize($user, 'private-user.'.$other->id, ['mobile'], self::FLUTTER_WEB_ORIGIN)
            ->assertForbidden()
            ->assertHeader('Access-Control-Allow-Origin', self::FLUTTER_WEB_ORIGIN);
    }

    #[Test]
    public function cors_does_not_let_a_non_admin_subscribe_to_the_admin_channel(): void
    {
        $this->configureReverbForAuthTests();
        $user = User::factory()->create();

        $this->authorize($user, 'private-admin', ['mobile'], self::ADMIN_WEB_ORIGIN)
            ->assertForbidden();
    }

    #[Test]
    public function a_browser_request_without_a_token_is_unauthenticated(): void
    {
        $this->withHeader('Origin', self::ADMIN_WEB_ORIGIN)
            ->postJson('/broadcasting/auth', [
                'channel_name' => 'private-admin',
                'socket_id' => '1234.5678',
            ])
            ->assertUnauthorized()
            ->assertHeader('Access-Control-Allow-Origin', self::ADMIN_WEB_ORIGIN);
    }
}
