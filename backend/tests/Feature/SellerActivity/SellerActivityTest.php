<?php

namespace Tests\Feature\SellerActivity;

use App\Enums\ActivityAction;
use App\Enums\UserRole;
use App\Models\Activity;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * `GET /api/seller/activities`.
 *
 * The feed is allow-listed and seller-scoped: only genuine events from the
 * existing activities table, only the caller's own, newest first, capped.
 */
class SellerActivityTest extends TestCase
{
    use RefreshDatabase;

    private User $seller;

    private User $otherSeller;

    private User $buyer;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seller = User::factory()->seller()->create(['role' => UserRole::User]);
        $this->otherSeller = User::factory()->seller()->create(['role' => UserRole::User]);
        $this->buyer = User::factory()->create(['role' => UserRole::User]);
    }

    private function token(User $user): string
    {
        return $user->createToken('mobile', ['mobile'])->plainTextToken;
    }

    /**
     * @param  array<string, mixed>  $metadata
     */
    private function activity(
        User $actor,
        ActivityAction $action,
        array $metadata = [],
        ?string $at = null,
    ): Activity {
        $activity = Activity::query()->create([
            'user_id' => $actor->id,
            'action' => $action->value,
            'description' => $action->label().' event',
            'metadata' => $metadata,
        ]);

        if ($at !== null) {
            DB::table('activities')->where('id', $activity->id)->update([
                'created_at' => $at,
                'updated_at' => $at,
            ]);
        }

        return $activity;
    }

    /**
     * @return array<int, array<string, mixed>>
     */
    private function listFor(User $user, string $query = ''): array
    {
        return $this->withHeader('Authorization', 'Bearer '.$this->token($user))
            ->getJson('/api/seller/activities'.$query)
            ->assertOk()
            ->json('data.activities');
    }

    #[Test]
    public function guests_cannot_read_the_feed(): void
    {
        $this->getJson('/api/seller/activities')->assertStatus(401);
    }

    #[Test]
    public function a_buyer_without_seller_capability_is_forbidden(): void
    {
        $this->withHeader('Authorization', 'Bearer '.$this->token($this->buyer))
            ->getJson('/api/seller/activities')
            ->assertForbidden();
    }

    #[Test]
    public function only_the_sellers_own_allow_listed_events_are_returned_newest_first(): void
    {
        $this->activity($this->buyer, ActivityAction::InquiryCreated, [
            'target_type' => 'inquiry',
            'target_id' => 11,
            'context' => ['seller_id' => $this->seller->id, 'listing_id' => 4],
        ], '2026-11-01 08:00:00');

        $this->activity($this->seller, ActivityAction::ListingMarkedSold, [
            'target_type' => 'listing',
            'target_id' => 4,
        ], '2026-11-02 09:00:00');

        $this->activity($this->buyer, ActivityAction::OfferAccepted, [
            'target_type' => 'offer',
            'target_id' => 21,
            'context' => [
                'seller_id' => $this->seller->id,
                'buyer_id' => $this->buyer->id,
                'transaction_id' => 31,
                'listing_id' => 4,
            ],
        ], '2026-11-03 10:00:00');

        // Another seller's event, a disallowed action for this seller, and
        // global audit noise must all be excluded.
        $this->activity($this->buyer, ActivityAction::InquiryCreated, [
            'context' => ['seller_id' => $this->otherSeller->id],
        ], '2026-11-04 11:00:00');
        $this->activity($this->seller, ActivityAction::ListingCreated, [], '2026-11-04 12:00:00');
        $this->activity($this->seller, ActivityAction::UserLoggedIn, [], '2026-11-04 13:00:00');
        $this->activity($this->buyer, ActivityAction::SettingsUpdated, [
            'context' => ['seller_id' => $this->seller->id],
        ], '2026-11-04 14:00:00');

        $activities = $this->listFor($this->seller);

        $this->assertCount(3, $activities);
        $this->assertSame(
            ['offer_accepted', 'listing_marked_sold', 'inquiry_created'],
            array_column($activities, 'action'),
        );
    }

    #[Test]
    public function admin_performed_events_are_scoped_to_the_affected_seller(): void
    {
        $admin = User::factory()->admin()->create();

        $this->activity($admin, ActivityAction::ListingApproved, [
            'target_type' => 'listing',
            'target_id' => 4,
            'context' => ['seller_id' => $this->seller->id],
        ], '2026-11-02 09:00:00');

        $this->activity($admin, ActivityAction::ListingRejected, [
            'target_type' => 'listing',
            'target_id' => 5,
            'context' => ['seller_id' => $this->otherSeller->id],
        ], '2026-11-03 09:00:00');

        $mine = $this->listFor($this->seller);
        $theirs = $this->listFor($this->otherSeller);

        $this->assertCount(1, $mine);
        $this->assertSame('listing_approved', $mine[0]['action']);
        $this->assertCount(1, $theirs);
        $this->assertSame('listing_rejected', $theirs[0]['action']);
    }

    #[Test]
    public function the_feed_defaults_to_five_and_honours_a_valid_limit(): void
    {
        for ($index = 1; $index <= 8; $index++) {
            $this->activity($this->buyer, ActivityAction::InquiryCreated, [
                'context' => ['seller_id' => $this->seller->id],
            ], '2026-11-0'.$index.' 08:00:00');
        }

        $this->assertCount(5, $this->listFor($this->seller));
        $this->assertCount(2, $this->listFor($this->seller, '?limit=2'));
    }

    #[Test]
    public function the_limit_is_bounded_and_ownership_filters_are_refused(): void
    {
        $this->withHeader('Authorization', 'Bearer '.$this->token($this->seller))
            ->getJson('/api/seller/activities?limit=21')
            ->assertStatus(422)
            ->assertJsonValidationErrors(['limit']);

        $this->withHeader('Authorization', 'Bearer '.$this->token($this->seller))
            ->getJson('/api/seller/activities?seller_id='.$this->otherSeller->id)
            ->assertStatus(422)
            ->assertJsonValidationErrors(['seller_id']);
    }

    #[Test]
    public function the_response_contract_is_safe_and_navigation_oriented(): void
    {
        $this->activity($this->buyer, ActivityAction::OfferAccepted, [
            'target_type' => 'offer',
            'target_id' => 21,
            'context' => [
                'seller_id' => $this->seller->id,
                'buyer_id' => $this->buyer->id,
                'transaction_id' => 31,
                'listing_id' => 4,
                'offer_id' => 21,
            ],
            'admin_note' => 'internal only',
            'changes' => ['status' => ['from' => 'pending', 'to' => 'accepted']],
        ], '2026-11-03 10:00:00');

        $activity = $this->listFor($this->seller)[0];

        $this->assertSame(
            ['id', 'action', 'label', 'description', 'created_at', 'target_type', 'target_id', 'context'],
            array_keys($activity),
        );
        $this->assertSame('Offer accepted', $activity['label']);
        $this->assertSame('offer', $activity['target_type']);
        $this->assertSame(21, $activity['target_id']);
        $this->assertSame(31, $activity['context']['transaction_id']);
        $this->assertSame(4, $activity['context']['listing_id']);
        $this->assertArrayNotHasKey('admin_note', $activity);
        $this->assertArrayNotHasKey('changes', $activity);
    }

    #[Test]
    public function an_event_without_navigation_context_serialises_context_as_an_object(): void
    {
        $this->activity($this->seller, ActivityAction::ListingMarkedSold, [
            'target_type' => 'listing',
            'target_id' => 4,
        ], '2026-11-02 09:00:00');

        $response = $this->withHeader('Authorization', 'Bearer '.$this->token($this->seller))
            ->getJson('/api/seller/activities')
            ->assertOk();

        // The mobile model reads `context` as an object. `[]` here is the bug
        // this test pins: it made every context-less event fail parsing.
        $this->assertStringContainsString('"context":{}', $response->getContent());
    }

    #[Test]
    public function a_seller_who_is_also_a_buyer_does_not_see_their_purchase_inquiry(): void
    {
        // Seller A bought from seller B: the inquiry_created actor is seller A,
        // but the event belongs to seller B (context.seller_id). This was the
        // observed leak (inquiry #9 / listing #123).
        $this->activity($this->seller, ActivityAction::InquiryCreated, [
            'target_type' => 'inquiry',
            'target_id' => 9,
            'context' => ['seller_id' => $this->otherSeller->id, 'listing_id' => 123],
        ], '2026-11-04 08:00:00');

        $this->assertSame([], $this->listFor($this->seller));

        $theirs = $this->listFor($this->otherSeller);
        $this->assertCount(1, $theirs);
        $this->assertSame('inquiry_created', $theirs[0]['action']);
    }

    #[Test]
    public function the_limit_shape_still_returns_the_existing_activities_and_adds_pagination(): void
    {
        for ($index = 1; $index <= 3; $index++) {
            $this->activity($this->buyer, ActivityAction::InquiryCreated, [
                'context' => ['seller_id' => $this->seller->id],
            ], '2026-11-0'.$index.' 08:00:00');
        }

        $response = $this->withHeader('Authorization', 'Bearer '.$this->token($this->seller))
            ->getJson('/api/seller/activities?limit=2')
            ->assertOk();

        $this->assertCount(2, $response->json('data.activities'));
        $this->assertSame(2, $response->json('data.pagination.per_page'));
        $this->assertSame(1, $response->json('data.pagination.current_page'));
        $this->assertSame(3, $response->json('data.pagination.total'));
    }

    #[Test]
    public function categories_filter_to_their_action_group(): void
    {
        $this->activity($this->buyer, ActivityAction::InquiryCreated, [
            'context' => ['seller_id' => $this->seller->id],
        ], '2026-11-01 08:00:00');
        $this->activity($this->seller, ActivityAction::OfferCreated, [
            'context' => ['seller_id' => $this->seller->id, 'buyer_id' => $this->buyer->id],
        ], '2026-11-02 08:00:00');
        $this->activity($this->seller, ActivityAction::ListingMarkedSold, [
            'target_type' => 'listing',
            'target_id' => 4,
        ], '2026-11-03 08:00:00');
        $this->activity($this->buyer, ActivityAction::TransactionCancelled, [
            'context' => ['seller_id' => $this->seller->id, 'transaction_id' => 7],
        ], '2026-11-04 08:00:00');

        $this->assertSame(
            ['inquiry_created'],
            array_column($this->listFor($this->seller, '?category=inquiries'), 'action'),
        );
        $this->assertSame(
            ['offer_created'],
            array_column($this->listFor($this->seller, '?category=offers'), 'action'),
        );
        $this->assertSame(
            ['listing_marked_sold'],
            array_column($this->listFor($this->seller, '?category=listings'), 'action'),
        );
        $this->assertSame(
            ['transaction_cancelled'],
            array_column($this->listFor($this->seller, '?category=transactions'), 'action'),
        );
        $this->assertCount(4, $this->listFor($this->seller));
    }

    #[Test]
    public function the_date_range_is_inclusive_and_together_with_pagination(): void
    {
        $this->activity($this->buyer, ActivityAction::InquiryCreated, [
            'context' => ['seller_id' => $this->seller->id],
        ], '2026-11-01 23:59:59');
        $this->activity($this->buyer, ActivityAction::InquiryCreated, [
            'context' => ['seller_id' => $this->seller->id],
        ], '2026-11-02 00:00:00');
        $this->activity($this->buyer, ActivityAction::InquiryCreated, [
            'context' => ['seller_id' => $this->seller->id],
        ], '2026-11-02 23:59:59');
        $this->activity($this->buyer, ActivityAction::InquiryCreated, [
            'context' => ['seller_id' => $this->seller->id],
        ], '2026-11-03 00:00:00');

        $response = $this->withHeader('Authorization', 'Bearer '.$this->token($this->seller))
            ->getJson('/api/seller/activities?from=2026-11-02&to=2026-11-02&per_page=1&page=2')
            ->assertOk();

        $this->assertSame(2, $response->json('data.pagination.total'));
        $this->assertSame(2, $response->json('data.pagination.last_page'));
        $this->assertSame(2, $response->json('data.pagination.current_page'));
        $this->assertCount(1, $response->json('data.activities'));
        $this->assertSame(
            '2026-11-02T00:00:00.000000Z',
            $response->json('data.activities.0.created_at'),
        );
    }

    #[Test]
    public function filters_and_pagination_never_widen_ownership(): void
    {
        $this->activity($this->buyer, ActivityAction::InquiryCreated, [
            'context' => ['seller_id' => $this->otherSeller->id],
        ], '2026-11-02 08:00:00');

        $response = $this->withHeader('Authorization', 'Bearer '.$this->token($this->seller))
            ->getJson('/api/seller/activities?category=inquiries&from=2026-11-01&to=2026-12-01&per_page=50')
            ->assertOk();

        $this->assertSame([], $response->json('data.activities'));
        $this->assertSame(0, $response->json('data.pagination.total'));
    }

    #[Test]
    public function invalid_filter_shapes_are_refused(): void
    {
        $base = $this->withHeader('Authorization', 'Bearer '.$this->token($this->seller));

        $base->getJson('/api/seller/activities?category=cattle')->assertStatus(422);
        $base->getJson('/api/seller/activities?from=2026-11-05&to=2026-11-01')->assertStatus(422);
        $base->getJson('/api/seller/activities?from=11/02/2026')->assertStatus(422);
        $base->getJson('/api/seller/activities?per_page=51')->assertStatus(422);
        $base->getJson('/api/seller/activities?limit=5&page=2')->assertStatus(422);
    }

    #[Test]
    public function an_empty_page_returns_an_empty_activity_list(): void
    {
        $this->assertSame([], $this->listFor($this->seller));
    }
}
