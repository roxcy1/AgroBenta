<?php

namespace Tests\Feature\Realtime;

use App\Enums\ListingStatus;
use App\Enums\SellerCapability;
use App\Enums\UserRole;
use App\Events\ActivityRecorded;
use App\Events\NotificationCreated;
use App\Models\Listing;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Illuminate\Testing\TestResponse;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Phase 4 — notification broadcast (mobile badge) and the shared admin channel.
 */
class Phase4BroadcastTest extends TestCase
{
    use RefreshDatabase;

    private User $buyer;

    private User $seller;

    protected function setUp(): void
    {
        parent::setUp();

        $this->buyer = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $this->seller = User::factory()->seller()->create([
            'role' => UserRole::User,
        ]);
    }

    private function token(User $user, array $abilities = ['mobile']): string
    {
        return $user->createToken('test', $abilities)->plainTextToken;
    }

    private function asUser(User $user, string $method, string $uri, array $body = []): TestResponse
    {
        return $this->withHeader('Authorization', 'Bearer '.$this->token($user))
            ->json($method, $uri, $body);
    }

    private function createListing(): Listing
    {
        return Listing::create([
            'seller_id' => $this->seller->id,
            'livestock_type' => 'cattle',
            'breed' => 'Angus',
            'age_value' => 2,
            'age_unit' => 'year',
            'gender' => 'male',
            'weight_value' => 500,
            'weight_unit' => 'kg',
            'quantity' => 2,
            'asking_price' => 50000.00,
            'location' => 'Bukidnon',
            'health_status' => 'healthy',
            'vaccination' => 'up_to_date',
            'short_description' => 'Healthy Angus bull',
            'additional_notes' => null,
            'photos' => [],
            'status' => ListingStatus::Active,
        ]);
    }

    private function createInquiry(Listing $listing): array
    {
        return $this->asUser($this->buyer, 'POST', '/api/inquiries', [
            'listing_id' => $listing->id,
            'message' => 'I am interested.',
            'payment_method' => 'cash',
            'collection_method' => 'farm_pickup',
        ])->assertStatus(201)->json('data');
    }

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

    #[Test]
    public function a_database_notification_broadcasts_to_the_recipients_channel(): void
    {
        Event::fake([NotificationCreated::class]);

        $listing = $this->createListing();
        $this->createInquiry($listing);

        Event::assertDispatched(NotificationCreated::class, function (NotificationCreated $event) {
            $channels = $event->broadcastOn();

            return count($channels) === 1
                && $channels[0]->name === 'private-user.'.$this->seller->id
                && $event->broadcastAs() === 'notification.created'
                && $event->broadcastWith()['type'] === 'inquiry';
        });
    }

    #[Test]
    public function an_audit_entry_broadcasts_to_the_shared_admin_channel(): void
    {
        Event::fake([ActivityRecorded::class]);

        $listing = $this->createListing();
        $this->createInquiry($listing);

        Event::assertDispatched(ActivityRecorded::class, function (ActivityRecorded $event) {
            $channels = $event->broadcastOn();

            return count($channels) === 1
                && $channels[0]->name === 'private-admin'
                && $event->broadcastAs() === 'activity.recorded'
                && $event->broadcastWith()['action'] === 'inquiry_created';
        });
    }

    #[Test]
    public function an_admin_can_subscribe_to_the_shared_admin_channel(): void
    {
        $this->configureReverbForAuthTests();

        $admin = User::factory()->admin()->create();

        $this->withHeader('Authorization', 'Bearer '.$this->token($admin, ['admin']))
            ->postJson('/broadcasting/auth', [
                'channel_name' => 'private-admin',
                'socket_id' => '1234.5678',
            ])->assertOk();
    }

    #[Test]
    public function a_non_admin_cannot_subscribe_to_the_shared_admin_channel(): void
    {
        $this->configureReverbForAuthTests();

        $this->withHeader('Authorization', 'Bearer '.$this->token($this->buyer))
            ->postJson('/broadcasting/auth', [
                'channel_name' => 'private-admin',
                'socket_id' => '1234.5678',
            ])->assertStatus(403);
    }
}
