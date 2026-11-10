<?php

namespace Tests\Feature\Realtime;

use App\Enums\ListingStatus;
use App\Enums\SellerCapability;
use App\Enums\UserRole;
use App\Events\InquiryCreated;
use App\Events\OfferCreated;
use App\Events\OfferUpdated;
use App\Events\TransactionCreated;
use App\Events\TransactionUpdated;
use App\Models\Listing;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Illuminate\Testing\TestResponse;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Phase 3 — real-time events are dispatched to the correct private channel.
 *
 * Drives the real HTTP API (inquiry -> offer -> transaction -> fulfillment) and
 * asserts that each mutation broadcasts the expected event to the counterparty's
 * `private-user.{id}` channel. The payloads are minimal pointers; the client
 * re-fetches the entity from the REST API.
 */
class RealtimeEventTest extends TestCase
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
            'name' => 'Pedro Reyes',
        ]);

        $this->seller = User::factory()->seller()->create([
            'role' => UserRole::User,
            'name' => 'Juan Dela Cruz',
        ]);
    }

    private function token(User $user): string
    {
        return $user->createToken('mobile', ['mobile'])->plainTextToken;
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

    /**
     * @return array{id: int, listing_id: int}
     */
    private function createInquiry(Listing $listing): array
    {
        return $this->asUser($this->buyer, 'POST', '/api/inquiries', [
            'listing_id' => $listing->id,
            'message' => 'I would like to buy this animal.',
            'payment_method' => 'cash',
            'collection_method' => 'farm_pickup',
        ])->assertStatus(201)->json('data');
    }

    private function assertBroadcastToUser(string $eventClass, int $userId, string $eventName, array $payload = []): void
    {
        Event::assertDispatched($eventClass, function ($event) use ($userId, $eventName, $payload) {
            $channels = $event->broadcastOn();
            $ok = count($channels) === 1
                && $channels[0]->name === 'private-user.'.$userId
                && $event->broadcastAs() === $eventName;

            foreach ($payload as $key => $value) {
                $ok = $ok && ($event->broadcastWith()[$key] ?? null) === $value;
            }

            return $ok;
        });
    }

    #[Test]
    public function inquiry_offer_and_acceptance_dispatch_events_to_the_counterparty(): void
    {
        Event::fake([
            InquiryCreated::class,
            OfferCreated::class,
            OfferUpdated::class,
            TransactionCreated::class,
        ]);

        $listing = $this->createListing();

        $inquiry = $this->createInquiry($listing);

        $this->assertBroadcastToUser(
            InquiryCreated::class,
            $this->seller->id,
            'inquiry.created',
            ['inquiry_id' => $inquiry['id'], 'listing_id' => $listing->id, 'buyer_id' => $this->buyer->id],
        );

        $offer = $this->asUser($this->seller, 'POST', '/api/offers', [
            'inquiry_id' => $inquiry['id'],
            'listing_id' => $listing->id,
            'proposed_amount' => '48000.00',
        ])->assertStatus(201)->json('data');

        $this->assertBroadcastToUser(
            OfferCreated::class,
            $this->buyer->id,
            'offer.created',
            ['offer_id' => $offer['id'], 'listing_id' => $listing->id, 'buyer_id' => $this->buyer->id],
        );

        $accepted = $this->asUser($this->buyer, 'POST', '/api/offers/'.$offer['id'].'/accept')
            ->assertOk()->json('data');

        $this->assertBroadcastToUser(
            OfferUpdated::class,
            $this->seller->id,
            'offer.updated',
            ['offer_id' => $offer['id'], 'status' => 'accepted', 'transaction_id' => $accepted['transaction']['id']],
        );

        $this->assertBroadcastToUser(
            TransactionCreated::class,
            $this->seller->id,
            'transaction.created',
            ['transaction_id' => $accepted['transaction']['id'], 'listing_id' => $listing->id],
        );
    }

    #[Test]
    public function declining_and_withdrawing_an_offer_notify_the_counterparty(): void
    {
        Event::fake([OfferUpdated::class]);

        $listing = $this->createListing();
        $inquiry = $this->createInquiry($listing);

        $offer = $this->asUser($this->seller, 'POST', '/api/offers', [
            'inquiry_id' => $inquiry['id'],
            'listing_id' => $listing->id,
            'proposed_amount' => '48000.00',
        ])->assertStatus(201)->json('data');

        // Buyer declines -> seller is the counterparty.
        $this->asUser($this->buyer, 'POST', '/api/offers/'.$offer['id'].'/decline')->assertOk();

        $this->assertBroadcastToUser(
            OfferUpdated::class,
            $this->seller->id,
            'offer.updated',
            ['offer_id' => $offer['id'], 'status' => 'declined'],
        );

        // A declined offer may be revised; seller withdraws the new one -> buyer.
        $revised = $this->asUser($this->seller, 'POST', '/api/offers', [
            'inquiry_id' => $inquiry['id'],
            'listing_id' => $listing->id,
            'proposed_amount' => '47000.00',
        ])->assertStatus(201)->json('data');

        $this->asUser($this->seller, 'POST', '/api/offers/'.$revised['id'].'/withdraw')->assertOk();

        $this->assertBroadcastToUser(
            OfferUpdated::class,
            $this->buyer->id,
            'offer.updated',
            ['offer_id' => $revised['id'], 'status' => 'withdrawn'],
        );
    }

    #[Test]
    public function a_direct_transaction_and_its_cancellation_notify_the_seller(): void
    {
        Event::fake([TransactionCreated::class, TransactionUpdated::class]);

        $listing = $this->createListing();

        $transaction = $this->asUser($this->buyer, 'POST', '/api/transactions', [
            'listing_id' => $listing->id,
            'quantity' => 1,
        ])->assertStatus(201)->json('data');

        $this->assertBroadcastToUser(
            TransactionCreated::class,
            $this->seller->id,
            'transaction.created',
            ['transaction_id' => $transaction['id'], 'listing_id' => $listing->id],
        );

        $this->asUser($this->buyer, 'POST', '/api/transactions/'.$transaction['id'].'/cancel')->assertOk();

        $this->assertBroadcastToUser(
            TransactionUpdated::class,
            $this->seller->id,
            'transaction.updated',
            ['transaction_id' => $transaction['id'], 'status' => 'cancelled'],
        );
    }

    #[Test]
    public function fulfillment_and_completion_notify_the_counterparty(): void
    {
        Event::fake([TransactionUpdated::class]);

        $listing = $this->createListing();
        $inquiry = $this->createInquiry($listing);

        $offer = $this->asUser($this->seller, 'POST', '/api/offers', [
            'inquiry_id' => $inquiry['id'],
            'listing_id' => $listing->id,
            'proposed_amount' => '48000.00',
        ])->assertStatus(201)->json('data');

        $transactionId = $this->asUser($this->buyer, 'POST', '/api/offers/'.$offer['id'].'/accept')
            ->assertOk()->json('data.transaction.id');

        // Seller starts preparing -> buyer is the counterparty.
        $this->asUser($this->seller, 'POST', '/api/transactions/'.$transactionId.'/preparing')->assertOk();

        $this->assertBroadcastToUser(
            TransactionUpdated::class,
            $this->buyer->id,
            'transaction.updated',
            ['transaction_id' => $transactionId, 'status' => 'pending', 'fulfillment_status' => 'preparing'],
        );

        // Buyer confirms receipt -> seller is the counterparty.
        $this->asUser($this->seller, 'POST', '/api/transactions/'.$transactionId.'/ready-for-pickup')->assertOk();
        $this->asUser($this->seller, 'POST', '/api/transactions/'.$transactionId.'/picked-up')->assertOk();
        $this->asUser($this->buyer, 'POST', '/api/transactions/'.$transactionId.'/complete')->assertOk();

        $this->assertBroadcastToUser(
            TransactionUpdated::class,
            $this->seller->id,
            'transaction.updated',
            ['transaction_id' => $transactionId, 'status' => 'completed', 'fulfillment_status' => 'completed'],
        );
    }
}
