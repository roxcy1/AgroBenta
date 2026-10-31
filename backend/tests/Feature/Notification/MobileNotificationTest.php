<?php

namespace Tests\Feature\Notification;

use App\Models\SellerVerification;
use App\Models\User;
use App\Notifications\ListingApproved;
use App\Notifications\TransactionCreated;
use App\Notifications\TransactionStatusChanged;
use App\Models\Listing;
use App\Models\Transaction;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Notification;
use Tests\TestCase;

/**
 * Feature tests for the mobile notification endpoints.
 *
 * Uses `Notification::fake()` throughout — the notification *firing* is
 * asserted via `Notification::assertSentTo(...)`, while the notification
 * *reading* (list, filter, mark, delete) exercises the real HTTP endpoints.
 * This split is what makes the tests robust against future notification
 * payload changes: a change to `data.title` breaks exactly one test, not all
 * of them.
 */
class MobileNotificationTest extends TestCase
{
    use RefreshDatabase;

    private function mobileUser(): array
    {
        $user = User::factory()->create();
        $token = $user->createToken('test', ['mobile'])->plainTextToken;

        return [$user, $token];
    }

    // ---------------------------------------------------------------------
    // Listing (index + pagination + filters)
    // ---------------------------------------------------------------------

    public function test_index_returns_caller_notifications_newest_first(): void
    {
        [$user, $token] = $this->mobileUser();

        $older = $user->notifications()->create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'type' => ListingApproved::class,
            'data' => ['type' => 'listings', 'title' => 'Old', 'body' => 'Older'],
            'read_at' => null,
            'created_at' => now()->subHours(2),
        ]);
        $newer = $user->notifications()->create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'type' => ListingApproved::class,
            'data' => ['type' => 'listings', 'title' => 'New', 'body' => 'Newer'],
            'read_at' => null,
            'created_at' => now(),
        ]);

        $this->actingAs($user, 'sanctum')
            ->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/notifications')
            ->assertOk()
            ->assertJsonPath('data.notifications.0.id', $newer->id)
            ->assertJsonPath('data.notifications.1.id', $older->id)
            ->assertJsonPath('data.unread_count', 2);
    }

    public function test_index_paginates(): void
    {
        [$user, $token] = $this->mobileUser();

        for ($i = 0; $i < 3; $i++) {
            $user->notifications()->create([
                'id' => (string) \Illuminate\Support\Str::uuid(),
                'type' => ListingApproved::class,
                'data' => ['type' => 'listings', 'title' => "N{$i}", 'body' => "B{$i}"],
            ]);
        }

        $this->actingAs($user, 'sanctum')
            ->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/notifications?per_page=2&page=1')
            ->assertOk()
            ->assertJsonCount(2, 'data.notifications')
            ->assertJsonPath('data.pagination.per_page', 2)
            ->assertJsonPath('data.pagination.total', 3)
            ->assertJsonPath('data.pagination.last_page', 2);
    }

    public function test_index_filters_by_unread(): void
    {
        [$user, $token] = $this->mobileUser();

        $user->notifications()->create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'type' => ListingApproved::class,
            'data' => ['type' => 'listings', 'title' => 'Unread', 'body' => ''],
            'read_at' => null,
        ]);
        $user->notifications()->create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'type' => ListingApproved::class,
            'data' => ['type' => 'listings', 'title' => 'Read', 'body' => ''],
            'read_at' => now(),
        ]);

        $this->actingAs($user, 'sanctum')
            ->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/notifications?unread=1')
            ->assertOk()
            ->assertJsonCount(1, 'data.notifications')
            ->assertJsonPath('data.notifications.0.title', 'Unread');
    }

    public function test_index_filters_by_type(): void
    {
        [$user, $token] = $this->mobileUser();

        $user->notifications()->create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'type' => ListingApproved::class,
            'data' => ['type' => 'listings', 'title' => 'Listing', 'body' => ''],
        ]);
        $user->notifications()->create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'type' => TransactionCreated::class,
            'data' => ['type' => 'transactions', 'title' => 'Txn', 'body' => ''],
        ]);

        $this->actingAs($user, 'sanctum')
            ->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/notifications?type=transactions')
            ->assertOk()
            ->assertJsonCount(1, 'data.notifications')
            ->assertJsonPath('data.notifications.0.title', 'Txn');
    }

    // ---------------------------------------------------------------------
    // Unread count
    // ---------------------------------------------------------------------

    public function test_unread_count_returns_the_caller_total(): void
    {
        [$user, $token] = $this->mobileUser();

        for ($i = 0; $i < 2; $i++) {
            $user->notifications()->create([
                'id' => (string) \Illuminate\Support\Str::uuid(),
                'type' => ListingApproved::class,
                'data' => ['type' => 'listings', 'title' => "N{$i}", 'body' => ''],
                'read_at' => null,
            ]);
        }

        $this->actingAs($user, 'sanctum')
            ->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/notifications/unread-count')
            ->assertOk()
            ->assertJsonPath('data.count', 2);
    }

    // ---------------------------------------------------------------------
    // Mark one
    // ---------------------------------------------------------------------

    public function test_mark_as_read_flips_the_flag(): void
    {
        [$user, $token] = $this->mobileUser();

        $notification = $user->notifications()->create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'type' => ListingApproved::class,
            'data' => ['type' => 'listings', 'title' => 'Test', 'body' => ''],
            'read_at' => null,
        ]);

        $this->actingAs($user, 'sanctum')
            ->withHeader('Authorization', "Bearer {$token}")
            ->patchJson("/api/notifications/{$notification->id}/read")
            ->assertOk()
            ->assertJsonPath('data.read', true);

        $this->assertNotNull($notification->fresh()->read_at);
    }

    public function test_mark_as_read_of_another_users_notification_is_404(): void
    {
        [$user, $token] = $this->mobileUser();
        $other = User::factory()->create();

        $foreign = $other->notifications()->create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'type' => ListingApproved::class,
            'data' => ['type' => 'listings', 'title' => 'Theirs', 'body' => ''],
        ]);

        $this->actingAs($user, 'sanctum')
            ->withHeader('Authorization', "Bearer {$token}")
            ->patchJson("/api/notifications/{$foreign->id}/read")
            ->assertNotFound();
    }

    // ---------------------------------------------------------------------
    // Mark all
    // ---------------------------------------------------------------------

    public function test_mark_all_as_read_returns_the_real_count(): void
    {
        [$user, $token] = $this->mobileUser();

        for ($i = 0; $i < 3; $i++) {
            $user->notifications()->create([
                'id' => (string) \Illuminate\Support\Str::uuid(),
                'type' => ListingApproved::class,
                'data' => ['type' => 'listings', 'title' => "N{$i}", 'body' => ''],
                'read_at' => null,
            ]);
        }

        $this->actingAs($user, 'sanctum')
            ->withHeader('Authorization', "Bearer {$token}")
            ->postJson('/api/notifications/read-all')
            ->assertOk()
            ->assertJsonPath('data.count', 3);

        $this->assertSame(0, $user->unreadNotifications()->count());
    }

    public function test_mark_all_as_read_when_nothing_unread_returns_zero(): void
    {
        [$user, $token] = $this->mobileUser();

        $this->actingAs($user, 'sanctum')
            ->withHeader('Authorization', "Bearer {$token}")
            ->postJson('/api/notifications/read-all')
            ->assertOk()
            ->assertJsonPath('data.count', 0);
    }

    // ---------------------------------------------------------------------
    // Delete
    // ---------------------------------------------------------------------

    public function test_destroy_removes_the_notification(): void
    {
        [$user, $token] = $this->mobileUser();

        $notification = $user->notifications()->create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'type' => ListingApproved::class,
            'data' => ['type' => 'listings', 'title' => 'Test', 'body' => ''],
        ]);

        $this->actingAs($user, 'sanctum')
            ->withHeader('Authorization', "Bearer {$token}")
            ->deleteJson("/api/notifications/{$notification->id}")
            ->assertOk();

        $this->assertNull($user->notifications()->find($notification->id));
    }

    public function test_destroy_of_another_users_notification_is_404(): void
    {
        [$user, $token] = $this->mobileUser();
        $other = User::factory()->create();

        $foreign = $other->notifications()->create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'type' => ListingApproved::class,
            'data' => ['type' => 'listings', 'title' => 'Theirs', 'body' => ''],
        ]);

        $this->actingAs($user, 'sanctum')
            ->withHeader('Authorization', "Bearer {$token}")
            ->deleteJson("/api/notifications/{$foreign->id}")
            ->assertNotFound();
    }

    // ---------------------------------------------------------------------
    // Transaction notifications (firing)
    // ---------------------------------------------------------------------

       public function test_creating_a_transaction_notifies_the_seller(): void
    {
        Notification::fake();

        $seller = User::factory()->create(['seller_capability' => 'seller']);
        $buyer  = User::factory()->create();

        // Listing has no factory — create it directly with every required
        // column. All non-nullable columns from the migration must be set
        // here, or the insert will fail with a constraint error.
        $listing = Listing::create([
            'seller_id' => $seller->getKey(),
            'livestock_type' => 'cattle',
            'breed' => 'Brahman',
            'quantity' => 10,
            'asking_price' => 1000,
            'location' => 'Trinidad, Bohol',
            'short_description' => 'Test listing',
            'status' => 'active',
            'photos' => [],
        ]);
       

        $buyerToken = $buyer->createToken('test', ['mobile'])->plainTextToken;

        $this->actingAs($buyer, 'sanctum')
            ->withHeader('Authorization', "Bearer {$buyerToken}")
            ->postJson('/api/transactions', [
                'listing_id' => $listing->getKey(),
                'quantity' => 2,
            ])
            ->assertCreated();

        Notification::assertSentTo($seller, TransactionCreated::class);
        Notification::assertNotSentTo($buyer, TransactionCreated::class);
    }
    public function test_cancelling_a_transaction_notifies_the_other_party(): void
    {
        Notification::fake();

        $seller = User::factory()->create(['seller_capability' => 'seller']);
        $buyer  = User::factory()->create();

        // Listing and Transaction have no factories. Create a real listing
        // first, then a transaction against it.
        $listing = Listing::create([
            'seller_id' => $seller->getKey(),
            'livestock_type' => 'cattle',
            'breed' => 'Brahman',
            'quantity' => 10,
            'asking_price' => 1000,
            'location' => 'Trinidad, Bohol',
            'short_description' => 'Test listing',
            'status' => 'active',
            'photos' => [],
        ]);

        $transaction = Transaction::create([
            'buyer_id' => $buyer->getKey(),
            'seller_id' => $seller->getKey(),
            'listing_id' => $listing->getKey(),
            'quantity' => 1,
            'total_amount' => 1000,
            'status' => 'pending',
        ]);
   

        $buyerToken = $buyer->createToken('test', ['mobile'])->plainTextToken;

        $this->actingAs($buyer, 'sanctum')
            ->withHeader('Authorization', "Bearer {$buyerToken}")
            ->postJson("/api/transactions/{$transaction->getKey()}/cancel")
            ->assertOk();

        Notification::assertSentTo($seller, TransactionStatusChanged::class);
    }
}