<?php

namespace Tests\Feature\Notification;

use App\Enums\ListingStatus;
use App\Jobs\SendPushNotification;
use App\Models\Listing;
use App\Models\NotificationPreference;
use App\Models\User;
use App\Notifications\ListingApproved;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Queue;
use Illuminate\Testing\TestResponse;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Notification Settings: the caller's push switches, and the push hook
 * honouring them. Every notification is still stored either way.
 */
class NotificationPreferenceTest extends TestCase
{
    use RefreshDatabase;

    private const ALL_ON = [
        'transactions' => true,
        'messages' => true,
        'listings' => true,
        'verification' => true,
    ];

    private function asMobile(User $user): static
    {
        return $this->withHeader(
            'Authorization',
            'Bearer '.$user->createToken('mobile', ['mobile'])->plainTextToken,
        );
    }

    private function update(User $user, array $body): TestResponse
    {
        return $this->asMobile($user)->putJson('/api/notification-preferences', $body);
    }

    private function approvedListingFor(User $seller): Listing
    {
        return Listing::create([
            'seller_id' => $seller->id,
            'livestock_type' => 'cattle',
            'breed' => 'Angus',
            'quantity' => 1,
            'asking_price' => 50000,
            'location' => 'Trinidad',
            'short_description' => 'Healthy Angus bull',
            'photos' => [],
            'status' => ListingStatus::Active,
        ]);
    }

    #[Test]
    public function a_user_without_settings_has_every_switch_on(): void
    {
        $this->asMobile(User::factory()->create())
            ->getJson('/api/notification-preferences')
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertExactJson([
                'success' => true,
                'message' => 'Notification settings retrieved.',
                'data' => self::ALL_ON,
            ]);

        $this->assertDatabaseCount('notification_preferences', 0);
    }

    #[Test]
    public function an_update_changes_only_the_switches_sent_and_returns_all(): void
    {
        $user = User::factory()->create();

        $this->update($user, ['listings' => false])
            ->assertOk()
            ->assertJsonPath('data', array_replace(self::ALL_ON, ['listings' => false]));

        $this->update($user, ['messages' => false])
            ->assertOk()
            ->assertJsonPath('data', array_replace(self::ALL_ON, ['listings' => false, 'messages' => false]));

        $this->update($user, ['listings' => true])
            ->assertOk()
            ->assertJsonPath('data', array_replace(self::ALL_ON, ['messages' => false]));

        $this->assertDatabaseCount('notification_preferences', 1);
    }

    #[Test]
    public function settings_belong_to_the_caller_only(): void
    {
        $user = User::factory()->create();
        $other = User::factory()->create();

        $this->update($user, ['transactions' => false])->assertOk();

        $this->asMobile($other)
            ->getJson('/api/notification-preferences')
            ->assertOk()
            ->assertJsonPath('data', self::ALL_ON);
    }

    #[Test]
    public function a_bad_update_is_refused(): void
    {
        $user = User::factory()->create();
        $other = User::factory()->create();

        $this->update($user, [])->assertUnprocessable()
            ->assertJsonValidationErrors(['transactions', 'messages', 'listings', 'verification']);

        $this->update($user, ['listings' => 'sometimes'])->assertUnprocessable()
            ->assertJsonValidationErrors(['listings']);

        $this->update($user, ['listings' => false, 'user_id' => $other->id])->assertUnprocessable()
            ->assertJsonValidationErrors(['user_id']);

        $this->assertDatabaseCount('notification_preferences', 0);
    }

    #[Test]
    public function the_settings_need_a_mobile_token(): void
    {
        $this->getJson('/api/notification-preferences')->assertUnauthorized();

        $admin = User::factory()->admin()->create();
        $this->withHeader('Authorization', 'Bearer '.$admin->createToken('admin', ['admin'])->plainTextToken)
            ->getJson('/api/notification-preferences')
            ->assertForbidden();
    }

    #[Test]
    public function a_switched_off_category_is_stored_but_not_pushed(): void
    {
        config(['services.fcm.credentials' => 'storage/app/firebase/test.json']);
        Queue::fake([SendPushNotification::class]);
        $seller = User::factory()->seller()->create();
        $this->update($seller, ['listings' => false])->assertOk();

        $seller->notify(new ListingApproved($this->approvedListingFor($seller)));

        Queue::assertNotPushed(SendPushNotification::class);
        $this->assertSame(1, $seller->notifications()->count());
    }

    #[Test]
    public function other_categories_are_still_pushed(): void
    {
        config(['services.fcm.credentials' => 'storage/app/firebase/test.json']);
        Queue::fake([SendPushNotification::class]);
        $seller = User::factory()->seller()->create();
        $this->update($seller, [
            'transactions' => false,
            'messages' => false,
            'verification' => false,
        ])->assertOk();

        $seller->notify(new ListingApproved($this->approvedListingFor($seller)));

        Queue::assertPushed(SendPushNotification::class, 1);
    }

    #[Test]
    public function each_notification_type_maps_to_one_switch(): void
    {
        $this->assertSame(
            [
                'transactions' => 'transactions',
                'inquiry' => 'messages',
                'listing' => 'listings',
                'seller_verification' => 'verification',
            ],
            NotificationPreference::CATEGORY_BY_TYPE,
        );
        $this->assertSame(
            NotificationPreference::CATEGORIES,
            array_values(array_unique(NotificationPreference::CATEGORY_BY_TYPE)),
        );
    }
}
