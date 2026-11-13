<?php

namespace Tests\Feature\Notification;

use App\Enums\ListingStatus;
use App\Enums\SellerCapability;
use App\Enums\UserRole;
use App\Jobs\SendPushNotification;
use App\Models\DeviceToken;
use App\Models\Listing;
use App\Models\User;
use App\Notifications\ListingApproved;
use App\Notifications\ListingRejected;
use App\Services\Push\FcmCredentials;
use App\Services\Push\PushNotificationService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Exceptions;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Queue;
use Illuminate\Testing\TestResponse;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Phone push notifications (FCM): device registration, the hook that queues a
 * push for every stored notification, and the FCM send itself.
 */
class PushNotificationTest extends TestCase
{
    use RefreshDatabase;

    private const FCM_URL = 'https://fcm.googleapis.com/v1/projects/agrobenta-test/messages:send';

    private User $seller;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seller = User::factory()->seller()->create(['role' => UserRole::User]);
    }

    private function registerDevice(User $user, string $token, array $abilities = ['mobile']): TestResponse
    {
        $bearer = $user->createToken('mobile', $abilities)->plainTextToken;

        return $this->withHeader('Authorization', 'Bearer '.$bearer)
            ->postJson('/api/devices', ['token' => $token]);
    }

    /**
     * Stand in for the Firebase service account, so no real key or Google
     * OAuth call is involved.
     */
    private function fakeCredentials(): void
    {
        $this->mock(FcmCredentials::class, function ($mock): void {
            $mock->shouldReceive('isConfigured')->andReturn(true);
            $mock->shouldReceive('projectId')->andReturn('agrobenta-test');
            $mock->shouldReceive('accessToken')->andReturn('test-access-token');
            $mock->shouldReceive('forgetAccessToken');
        });
    }

    private function addDevice(User $user, string $token): DeviceToken
    {
        $accessToken = $user->createToken('mobile', ['mobile'])->accessToken;

        return DeviceToken::create([
            'user_id' => $user->id,
            'personal_access_token_id' => $accessToken->id,
            'token' => $token,
        ]);
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
            'quantity' => 1,
            'asking_price' => 50000.00,
            'location' => 'Trinidad',
            'health_status' => 'healthy',
            'vaccination' => 'up_to_date',
            'short_description' => 'Healthy Angus bull',
            'additional_notes' => null,
            'photos' => [],
            'status' => ListingStatus::Active,
        ]);
    }

    // --- Device registration -------------------------------------------------

    #[Test]
    public function a_phone_registers_its_token_for_the_signed_in_session(): void
    {
        $this->registerDevice($this->seller, 'fcm-token-1')
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonMissingPath('data.token');

        $device = DeviceToken::query()->sole();

        $this->assertSame($this->seller->id, $device->user_id);
        $this->assertSame($this->seller->tokens()->sole()->id, $device->personal_access_token_id);
        $this->assertSame('fcm-token-1', $device->token);
    }

    #[Test]
    public function registering_the_same_token_again_keeps_one_row(): void
    {
        $this->registerDevice($this->seller, 'fcm-token-1')->assertOk();
        $this->registerDevice($this->seller, 'fcm-token-1')->assertOk();

        $this->assertDatabaseCount('device_tokens', 1);
    }

    #[Test]
    public function a_phone_that_signs_in_to_another_account_moves_to_it(): void
    {
        $buyer = User::factory()->create(['seller_capability' => SellerCapability::Buyer]);

        $this->registerDevice($this->seller, 'shared-phone')->assertOk();
        $this->registerDevice($buyer, 'shared-phone')->assertOk();

        $this->assertSame($buyer->id, DeviceToken::query()->sole()->user_id);
    }

    #[Test]
    public function the_token_is_required_and_a_user_id_is_refused(): void
    {
        $bearer = $this->seller->createToken('mobile', ['mobile'])->plainTextToken;

        $this->withHeader('Authorization', 'Bearer '.$bearer)
            ->postJson('/api/devices', [])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['token']);

        $other = User::factory()->create();

        $this->withHeader('Authorization', 'Bearer '.$bearer)
            ->postJson('/api/devices', ['token' => 'fcm-token-1', 'user_id' => $other->id])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['user_id']);

        $this->assertDatabaseCount('device_tokens', 0);
    }

    #[Test]
    public function registration_needs_a_mobile_token(): void
    {
        $this->postJson('/api/devices', ['token' => 'fcm-token-1'])->assertUnauthorized();

        $admin = User::factory()->admin()->create();
        $this->registerDevice($admin, 'fcm-token-1', ['admin'])->assertForbidden();

        $this->assertDatabaseCount('device_tokens', 0);
    }

    #[Test]
    public function logging_out_removes_the_phones_registration(): void
    {
        $bearer = $this->seller->createToken('mobile', ['mobile'])->plainTextToken;

        $this->withHeader('Authorization', 'Bearer '.$bearer)
            ->postJson('/api/devices', ['token' => 'fcm-token-1'])
            ->assertOk();

        $this->withHeader('Authorization', 'Bearer '.$bearer)
            ->postJson('/api/auth/logout')
            ->assertOk();

        $this->assertDatabaseCount('device_tokens', 0);
    }

    // --- Queuing a push for each stored notification ------------------------

    #[Test]
    public function a_stored_notification_queues_a_push_when_push_is_configured(): void
    {
        config(['services.fcm.credentials' => 'storage/app/firebase/test.json']);
        Queue::fake([SendPushNotification::class]);
        $listing = $this->createListing();

        $this->seller->notify(new ListingApproved($listing));

        $notificationId = $this->seller->notifications()->sole()->id;

        Queue::assertPushed(SendPushNotification::class, fn (SendPushNotification $job) => $job->userId === $this->seller->id
            && $job->title === 'Listing approved'
            && $job->data === [
                'notification_id' => $notificationId,
                'type' => 'listing',
                'action' => 'listing',
                'action_id' => (string) $listing->id,
            ]);
    }

    #[Test]
    public function no_push_is_queued_when_push_is_not_configured(): void
    {
        config(['services.fcm.credentials' => null]);
        Queue::fake([SendPushNotification::class]);

        $this->seller->notify(new ListingApproved($this->createListing()));

        Queue::assertNotPushed(SendPushNotification::class);
        $this->assertSame(1, $this->seller->notifications()->count());
    }

    // --- Sending through FCM -------------------------------------------------

    #[Test]
    public function a_push_goes_to_each_of_the_users_phones_and_no_one_elses(): void
    {
        $this->fakeCredentials();
        Http::fake([self::FCM_URL => Http::response(['name' => 'projects/agrobenta-test/messages/1'])]);

        $this->addDevice($this->seller, 'seller-phone-1');
        $this->addDevice($this->seller, 'seller-phone-2');
        $this->addDevice(User::factory()->create(), 'someone-elses-phone');

        app(PushNotificationService::class)->sendToUser($this->seller->id, 'Listing approved', [
            'type' => 'listing',
            'action' => 'listing',
            'action_id' => '5',
        ]);

        Http::assertSentCount(2);
        Http::assertSent(fn (Request $request) => $request->url() === self::FCM_URL
            && $request->hasHeader('Authorization', 'Bearer test-access-token')
            && $request['message']['token'] === 'seller-phone-1'
            && $request['message']['notification'] === [
                'title' => 'Listing approved',
                'body' => PushNotificationService::BODY,
            ]
            && $request['message']['data'] === ['type' => 'listing', 'action' => 'listing', 'action_id' => '5']);
        Http::assertSent(fn (Request $request) => $request['message']['token'] === 'seller-phone-2');
        Http::assertNotSent(fn (Request $request) => $request['message']['token'] === 'someone-elses-phone');
    }

    #[Test]
    public function the_push_text_never_carries_the_stored_notification_body(): void
    {
        config(['services.fcm.credentials' => 'storage/app/firebase/test.json']);
        $this->fakeCredentials();
        Http::fake([self::FCM_URL => Http::response(['name' => 'ok'])]);
        $this->addDevice($this->seller, 'seller-phone-1');

        $listing = $this->createListing();
        $listing->admin_note = 'Private reviewer note';

        $this->seller->notify(new ListingRejected($listing));

        $this->assertStringContainsString(
            'Private reviewer note',
            $this->seller->notifications()->sole()->data['body'],
        );

        Http::assertSent(fn (Request $request) => $request['message']['notification']['body'] === PushNotificationService::BODY
            && ! str_contains(json_encode($request->data()), 'Private reviewer note'));
    }

    #[Test]
    public function nothing_is_sent_to_a_user_with_no_registered_phone(): void
    {
        $this->fakeCredentials();
        Http::fake();

        app(PushNotificationService::class)->sendToUser($this->seller->id, 'Listing approved', []);

        Http::assertNothingSent();
    }

    #[Test]
    public function a_token_firebase_no_longer_knows_is_deleted(): void
    {
        $this->fakeCredentials();
        Http::fake([self::FCM_URL => Http::sequence()
            ->push(['error' => ['code' => 404, 'status' => 'NOT_FOUND']], 404)
            ->push(['error' => [
                'code' => 400,
                'status' => 'INVALID_ARGUMENT',
                'details' => [['@type' => 'type.googleapis.com/google.firebase.fcm.v1.FcmError', 'errorCode' => 'UNREGISTERED']],
            ]], 400)
            ->push(['name' => 'ok']),
        ]);

        $this->addDevice($this->seller, 'gone-404');
        $this->addDevice($this->seller, 'gone-unregistered');
        $this->addDevice($this->seller, 'still-valid');

        app(PushNotificationService::class)->sendToUser($this->seller->id, 'Listing approved', []);

        $this->assertSame(['still-valid'], DeviceToken::query()->pluck('token')->all());
    }

    #[Test]
    public function a_failed_send_keeps_the_token_and_reports_no_secrets(): void
    {
        Exceptions::fake();
        $this->fakeCredentials();
        Http::fake([self::FCM_URL => Http::sequence()
            ->push(['error' => ['code' => 500, 'message' => 'internal']], 500)
            ->pushFailedConnection('cURL error 28 for secret-device-token'),
        ]);

        $this->addDevice($this->seller, 'secret-device-token');
        $this->addDevice($this->seller, 'second-device-token');

        app(PushNotificationService::class)->sendToUser($this->seller->id, 'Listing approved', []);

        $this->assertDatabaseCount('device_tokens', 2);
        Exceptions::assertReported(fn (\RuntimeException $e) => $e->getMessage() === 'FCM send failed with HTTP 500.');
        Exceptions::assertReported(fn (\RuntimeException $e) => str_starts_with($e->getMessage(), 'FCM send request failed ('));

        foreach (Exceptions::reported() as $exception) {
            for ($e = $exception; $e !== null; $e = $e->getPrevious()) {
                $this->assertStringNotContainsString('device-token', $e->getMessage());
                $this->assertStringNotContainsString('test-access-token', $e->getMessage());
            }
        }
    }
}
