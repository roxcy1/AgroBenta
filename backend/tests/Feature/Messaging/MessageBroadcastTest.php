<?php

namespace Tests\Feature\Messaging;

use App\Events\MessageSent;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Reverb private-channel authorization and message broadcasting.
 *
 * Covers the two halves of Phase 2: (1) `MessageSent` is dispatched to the
 * receiver's `private-user.{id}` channel after a message is sent, and (2) the
 * `/broadcasting/auth` endpoint enforces the channel callbacks in
 * `routes/channels.php` (self-only `user.{id}`, admin-only `admin.{id}`).
 */
class MessageBroadcastTest extends TestCase
{
    use RefreshDatabase;

    private User $buyer;

    private User $seller;

    protected function setUp(): void
    {
        parent::setUp();

        $this->buyer = User::factory()->create();
        $this->seller = User::factory()->create();
    }

    /**
     * Point the default broadcaster at `reverb` with local test credentials so
     * the channel callbacks are actually exercised. The `null`/`log`
     * broadcasters no-op in `auth()`, and `authorizeChannel` is a local HMAC,
     * so no network is involved. The callbacks were first registered on the
     * boot-time default (`null`) broadcaster, so re-require the channels file
     * to register them on the now-active `reverb` one.
     *
     * Scoped to the auth tests only: the message-broadcast test keeps the
     * default `null` broadcaster, so the notification side-effect broadcast
     * stays a no-op instead of reaching a real Reverb server.
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

    private function tokenFor(User $user, array $abilities = ['mobile']): string
    {
        return $user->createToken('test', $abilities)->plainTextToken;
    }

    private function sendMessage(User $sender, int $receiverId, string $body): \Illuminate\Testing\TestResponse
    {
        return $this->withHeader('Authorization', 'Bearer '.$this->tokenFor($sender))
            ->postJson('/api/messages', [
                'receiver_id' => $receiverId,
                'body' => $body,
            ]);
    }

    private function subscribe(User $user, string $channelName, array $abilities = ['mobile']): \Illuminate\Testing\TestResponse
    {
        return $this->withHeader('Authorization', 'Bearer '.$this->tokenFor($user, $abilities))
            ->postJson('/broadcasting/auth', [
                'channel_name' => $channelName,
                'socket_id' => '1234.5678',
            ]);
    }

    #[Test]
    public function sending_a_message_broadcasts_to_the_receivers_private_channel(): void
    {
        Event::fake([MessageSent::class]);

        $this->sendMessage($this->buyer, $this->seller->id, 'Hello seller')
            ->assertStatus(201);

        Event::assertDispatched(MessageSent::class, function (MessageSent $event) {
            $channels = $event->broadcastOn();

            return count($channels) === 1
                && $channels[0]->name === 'private-user.'.$this->seller->id
                && $event->broadcastAs() === 'message.sent'
                && $event->broadcastWith()['sender_id'] === $this->buyer->id
                && $event->broadcastWith()['receiver_id'] === $this->seller->id
                && $event->broadcastWith()['body'] === 'Hello seller';
        });
    }

    #[Test]
    public function a_guest_cannot_authenticate_a_channel_subscription(): void
    {
        $this->postJson('/broadcasting/auth', [
            'channel_name' => 'private-user.'.$this->buyer->id,
            'socket_id' => '1234.5678',
        ])->assertStatus(401);
    }

    #[Test]
    public function a_user_can_subscribe_to_their_own_channel(): void
    {
        $this->configureReverbForAuthTests();

        $this->subscribe($this->buyer, 'private-user.'.$this->buyer->id)
            ->assertOk();
    }

    #[Test]
    public function a_user_cannot_subscribe_to_another_users_channel(): void
    {
        $this->configureReverbForAuthTests();

        $this->subscribe($this->buyer, 'private-user.'.$this->seller->id)
            ->assertStatus(403);
    }

    #[Test]
    public function an_admin_can_subscribe_to_their_admin_channel(): void
    {
        $this->configureReverbForAuthTests();

        $admin = User::factory()->admin()->create();

        $this->subscribe($admin, 'private-admin.'.$admin->id, ['admin'])
            ->assertOk();
    }

    #[Test]
    public function a_non_admin_cannot_subscribe_to_an_admin_channel(): void
    {
        $this->configureReverbForAuthTests();

        $this->subscribe($this->buyer, 'private-admin.'.$this->buyer->id)
            ->assertStatus(403);
    }
}
