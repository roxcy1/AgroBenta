<?php

namespace Tests\Feature\Messaging;

use App\Enums\ListingStatus;
use App\Enums\TransactionStatus;
use App\Events\MessageSent;
use App\Models\Inquiry;
use App\Models\Listing;
use App\Models\Message;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Notification;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class MessageHardeningTest extends TestCase
{
    use RefreshDatabase;

    private User $buyer;

    private User $seller;

    private User $otherBuyer;

    /** @var array<int, string> */
    private array $tokens = [];

    protected function setUp(): void
    {
        parent::setUp();

        $this->buyer = User::factory()->create([
            'name' => 'Buyer One',
            'email' => 'buyer-one@example.test',
        ]);
        $this->seller = User::factory()->seller()->create([
            'name' => 'Seller One',
            'email' => 'seller-one@example.test',
        ]);
        $this->otherBuyer = User::factory()->create([
            'name' => 'Buyer Two',
            'email' => 'buyer-two@example.test',
        ]);
    }

    private function mobileToken(User $user): string
    {
        return $this->tokens[$user->id] ??= $user
            ->createToken('mobile', ['mobile'])
            ->plainTextToken;
    }

    private function asUser(User $user): self
    {
        // Sanctum's RequestGuard caches its resolved user within the test app.
        $this->app->make('auth')->forgetGuards();

        return $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($user));
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function createListing(User $owner, array $overrides = []): Listing
    {
        return Listing::create(array_merge([
            'seller_id' => $owner->id,
            'livestock_type' => 'cattle',
            'breed' => 'Angus',
            'age_value' => 2,
            'age_unit' => 'year',
            'gender' => 'male',
            'weight_value' => 500,
            'weight_unit' => 'kg',
            'quantity' => 5,
            'asking_price' => 50000.00,
            'location' => 'Bukidnon',
            'health_status' => 'healthy',
            'vaccination' => 'up_to_date',
            'short_description' => 'Healthy Angus bull',
            'additional_notes' => null,
            'photos' => [],
            'status' => ListingStatus::Active,
            'inventory_reconciliation_required' => false,
        ], $overrides));
    }

    private function createInquiry(User $buyer, User $seller, Listing $listing): Inquiry
    {
        return Inquiry::create([
            'buyer_id' => $buyer->id,
            'seller_id' => $seller->id,
            'listing_id' => $listing->id,
            'subject' => 'Is this still available?',
            'message' => 'I would like to buy this animal.',
            'status' => 'open',
        ]);
    }

    private function createTransaction(User $buyer, User $seller, Listing $listing): Transaction
    {
        return Transaction::create([
            'buyer_id' => $buyer->id,
            'seller_id' => $seller->id,
            'listing_id' => $listing->id,
            'quantity' => 1,
            'total_amount' => 48000.00,
            'status' => TransactionStatus::Pending,
        ]);
    }

    /**
     * @param  array<string, mixed>  $extra
     */
    private function sendMessage(User $sender, User $receiver, array $extra = [])
    {
        return $this->asUser($sender)->postJson('/api/messages', array_merge([
            'receiver_id' => $receiver->id,
            'body' => 'Hello from AgroBenta.',
        ], $extra));
    }

    #[Test]
    public function sender_and_read_fields_are_rejected_even_when_empty(): void
    {
        $cases = [
            [['sender_id' => $this->seller->id], ['sender_id']],
            [['sender_id' => null], ['sender_id']],
            [['sender_id' => ''], ['sender_id']],
            [['read_at' => '2026-11-23T10:00:00Z'], ['read_at']],
            [['read_at' => null], ['read_at']],
            [['read_at' => ''], ['read_at']],
            [
                ['sender_id' => $this->seller->id, 'read_at' => '2026-11-23T10:00:00Z'],
                ['sender_id', 'read_at'],
            ],
        ];

        foreach ($cases as [$body, $fields]) {
            $this->sendMessage($this->buyer, $this->seller, $body)
                ->assertUnprocessable()
                ->assertJsonValidationErrors($fields);
        }

        $this->assertSame(0, Message::query()->count());
    }

    #[Test]
    public function valid_message_uses_the_authenticated_sender_and_unread_timestamp(): void
    {
        $message = $this->sendMessage($this->buyer, $this->seller)
            ->assertCreated()
            ->assertJsonPath('data.sender_id', $this->buyer->id)
            ->assertJsonPath('data.receiver_id', $this->seller->id)
            ->assertJsonPath('data.read_at', null)
            ->json('data');

        $this->assertSame($this->buyer->id, $message['sender_id']);
        $this->assertDatabaseHas('messages', [
            'id' => $message['id'],
            'sender_id' => $this->buyer->id,
            'read_at' => null,
        ]);
    }

    #[Test]
    public function message_limiter_is_thirty_per_minute_per_user_and_route_scoped(): void
    {
        Event::fake([MessageSent::class]);
        Notification::fake();

        for ($attempt = 1; $attempt <= 30; $attempt++) {
            $this->sendMessage($this->buyer, $this->seller, [
                'body' => 'Valid message '.$attempt,
            ])->assertCreated();
        }

        $limited = $this->sendMessage($this->buyer, $this->seller, [
            'body' => 'Over the limit',
        ])->assertStatus(429)->assertHeader('Retry-After');

        $this->assertSame(30, Message::query()->count());
        $this->assertPrivateEmailsAbsent($limited->getContent());
        Event::assertDispatchedTimes(MessageSent::class, 30);

        // A second account has an independent quota; this is not a global API
        // throttle, and the profile endpoint remains available to the first user.
        $this->sendMessage($this->otherBuyer, $this->seller)->assertCreated();
        $this->asUser($this->buyer)->getJson('/api/profile')->assertOk();

        $this->travel(61)->seconds();
        $this->sendMessage($this->buyer, $this->seller)->assertCreated();

        $this->assertSame(32, Message::query()->count());
        Event::assertDispatchedTimes(MessageSent::class, 32);
    }

    #[Test]
    public function listing_context_accepts_public_and_sender_owned_listings(): void
    {
        $publicListing = $this->createListing($this->seller);
        $this->sendMessage($this->buyer, $this->seller, [
            'listing_id' => $publicListing->id,
        ])->assertCreated();

        $ownedDraft = $this->createListing($this->buyer, [
            'status' => ListingStatus::Draft,
        ]);
        $this->sendMessage($this->buyer, $this->seller, [
            'listing_id' => $ownedDraft->id,
        ])->assertCreated();
    }

    #[Test]
    public function a_buyer_can_reply_after_a_pending_transaction_reserves_all_active_listing_stock(): void
    {
        Event::fake([MessageSent::class]);
        Notification::fake();

        $listing = $this->createListing($this->seller, [
            'quantity' => 1,
            'total_quantity' => 1,
        ]);

        $transaction = $this->asUser($this->buyer)
            ->postJson('/api/transactions', [
                'listing_id' => $listing->id,
                'quantity' => 1,
            ])
            ->assertCreated()
            ->json('data');

        $this->assertDatabaseHas('transactions', [
            'id' => $transaction['id'],
            'buyer_id' => $this->buyer->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'status' => TransactionStatus::Pending->value,
            'inventory_reserved' => true,
        ]);
        $this->assertSame(0, $listing->refresh()->quantity);
        $this->assertSame(ListingStatus::Active, $listing->status);

        $message = $this->sendMessage($this->buyer, $this->seller, [
            'listing_id' => $listing->id,
        ])
            ->assertCreated()
            ->assertJsonPath('data.sender_id', $this->buyer->id)
            ->assertJsonPath('data.receiver_id', $this->seller->id)
            ->assertJsonPath('data.listing_id', $listing->id)
            ->json('data');

        $this->assertDatabaseHas('messages', [
            'id' => $message['id'],
            'sender_id' => $this->buyer->id,
            'receiver_id' => $this->seller->id,
            'listing_id' => $listing->id,
        ]);
    }

    #[Test]
    public function active_unavailable_listings_require_an_exact_inquiry_or_transaction_relationship(): void
    {
        $unreconciledWithInquiry = $this->createListing($this->seller, [
            'quantity' => 0,
            'inventory_reconciliation_required' => true,
        ]);
        $this->createInquiry($this->buyer, $this->seller, $unreconciledWithInquiry);

        $this->sendMessage($this->buyer, $this->seller, [
            'listing_id' => $unreconciledWithInquiry->id,
        ])->assertCreated();

        $activeWithTransaction = $this->createListing($this->seller, [
            'quantity' => 0,
        ]);
        $this->createTransaction($this->buyer, $this->seller, $activeWithTransaction);

        $this->sendMessage($this->buyer, $this->seller, [
            'listing_id' => $activeWithTransaction->id,
        ])->assertCreated();

        $activeWithOtherPairTransaction = $this->createListing($this->seller, [
            'quantity' => 0,
        ]);
        $this->createTransaction($this->otherBuyer, $this->seller, $activeWithOtherPairTransaction);

        $this->sendMessage($this->buyer, $this->seller, [
            'listing_id' => $activeWithOtherPairTransaction->id,
        ])->assertUnprocessable()->assertJsonValidationErrors('listing_id');

        $activeWithDifferentListingRelationship = $this->createListing($this->seller, [
            'quantity' => 0,
        ]);
        $this->createTransaction($this->buyer, $this->seller, $activeWithTransaction);

        $this->sendMessage($this->buyer, $this->seller, [
            'listing_id' => $activeWithDifferentListingRelationship->id,
        ])->assertUnprocessable()->assertJsonValidationErrors('listing_id');
    }

    #[Test]
    public function hidden_listing_contexts_are_refused_without_persisting_or_disclosing_them(): void
    {
        Event::fake([MessageSent::class]);

        $hiddenListings = [
            $this->createListing($this->otherBuyer, ['status' => ListingStatus::Draft]),
            $this->createListing($this->otherBuyer, ['status' => ListingStatus::Pending]),
            $this->createListing($this->otherBuyer, ['status' => ListingStatus::Inactive]),
            $this->createListing($this->otherBuyer, ['status' => ListingStatus::Sold]),
            $this->createListing($this->otherBuyer, ['quantity' => 0]),
            $this->createListing($this->otherBuyer, [
                'inventory_reconciliation_required' => true,
            ]),
        ];

        foreach ($hiddenListings as $listing) {
            $response = $this->sendMessage($this->buyer, $this->seller, [
                'listing_id' => $listing->id,
            ])->assertUnprocessable()
                ->assertJsonValidationErrors('listing_id');

            $this->assertStringNotContainsString($listing->breed, $response->getContent());
        }

        $this->sendMessage($this->buyer, $this->seller, [
            'listing_id' => 999999,
        ])->assertUnprocessable()->assertJsonValidationErrors('listing_id');

        $this->assertSame(0, Message::query()->count());
        $this->asUser($this->buyer)
            ->getJson('/api/conversations')
            ->assertOk()
            ->assertJsonPath('data.conversations', []);
        Event::assertNotDispatched(MessageSent::class);
    }

    #[Test]
    public function sold_and_inactive_contexts_require_an_exact_historical_relationship(): void
    {
        $soldWithTransaction = $this->createListing($this->seller, [
            'status' => ListingStatus::Sold,
        ]);
        $this->createTransaction($this->buyer, $this->seller, $soldWithTransaction);

        $inactiveWithInquiry = $this->createListing($this->seller, [
            'status' => ListingStatus::Inactive,
        ]);
        $this->createInquiry($this->buyer, $this->seller, $inactiveWithInquiry);

        $inactiveWithMessage = $this->createListing($this->seller, [
            'status' => ListingStatus::Inactive,
        ]);
        Message::create([
            'sender_id' => $this->buyer->id,
            'receiver_id' => $this->seller->id,
            'listing_id' => $inactiveWithMessage->id,
            'body' => 'An existing authorized conversation.',
        ]);

        foreach ([$soldWithTransaction, $inactiveWithInquiry, $inactiveWithMessage] as $listing) {
            $this->sendMessage($this->buyer, $this->seller, [
                'listing_id' => $listing->id,
            ])->assertCreated();
        }

        $sameListingDifferentPair = $this->createListing($this->seller, [
            'status' => ListingStatus::Inactive,
        ]);
        $this->createTransaction($this->otherBuyer, $this->seller, $sameListingDifferentPair);

        $otherListingSamePair = $this->createListing($this->seller, [
            'status' => ListingStatus::Inactive,
        ]);
        $this->createTransaction($this->buyer, $this->seller, $otherListingSamePair);

        $this->sendMessage($this->buyer, $this->otherBuyer, [
            'listing_id' => $sameListingDifferentPair->id,
        ])->assertUnprocessable()->assertJsonValidationErrors('listing_id');

        $unrelatedListing = $this->createListing($this->otherBuyer, [
            'status' => ListingStatus::Inactive,
        ]);
        $this->sendMessage($this->buyer, $this->seller, [
            'listing_id' => $unrelatedListing->id,
        ])->assertUnprocessable()->assertJsonValidationErrors('listing_id');
    }

    #[Test]
    public function a_historical_pair_reference_does_not_authorize_other_hidden_listing_states(): void
    {
        $pending = $this->createListing($this->seller, [
            'status' => ListingStatus::Pending,
        ]);
        $draftOwnedByAnotherUser = $this->createListing($this->seller, [
            'status' => ListingStatus::Draft,
        ]);
        $unavailableActive = $this->createListing($this->seller, [
            'quantity' => 0,
        ]);

        $this->createTransaction($this->buyer, $this->seller, $pending);
        $this->createInquiry($this->buyer, $this->seller, $draftOwnedByAnotherUser);

        foreach ([$pending, $draftOwnedByAnotherUser, $unavailableActive] as $listing) {
            Message::create([
                'sender_id' => $this->buyer->id,
                'receiver_id' => $this->seller->id,
                'listing_id' => $listing->id,
                'body' => 'Legacy listing context',
            ]);

            $this->sendMessage($this->buyer, $this->seller, [
                'listing_id' => $listing->id,
            ])->assertUnprocessable()->assertJsonValidationErrors('listing_id');
        }
    }

    #[Test]
    public function pair_wide_history_and_read_receipts_include_unlisted_messages(): void
    {
        $firstListing = $this->createListing($this->seller);
        $secondListing = $this->createListing($this->seller, [
            'livestock_type' => 'goat',
            'breed' => 'Boer',
        ]);
        $first = Message::create([
            'sender_id' => $this->seller->id,
            'receiver_id' => $this->buyer->id,
            'listing_id' => $firstListing->id,
            'body' => 'About cattle',
        ]);
        $second = Message::create([
            'sender_id' => $this->seller->id,
            'receiver_id' => $this->buyer->id,
            'listing_id' => $secondListing->id,
            'body' => 'About goats',
        ]);
        $unlisted = Message::create([
            'sender_id' => $this->seller->id,
            'receiver_id' => $this->buyer->id,
            'listing_id' => null,
            'body' => 'A general follow-up',
        ]);
        $unrelated = Message::create([
            'sender_id' => $this->otherBuyer->id,
            'receiver_id' => $this->buyer->id,
            'listing_id' => $firstListing->id,
            'body' => 'A different pair',
        ]);

        $thread = $this->asUser($this->buyer)
            ->getJson('/api/conversations/'.$this->seller->id.'/messages')
            ->assertOk()
            ->json('data.messages');
        $this->assertEqualsCanonicalizing(
            [$first->id, $second->id, $unlisted->id],
            array_column($thread, 'id'),
        );

        $filtered = $this->asUser($this->buyer)
            ->getJson('/api/conversations/'.$this->seller->id.'/messages?listing_id='.$firstListing->id)
            ->assertOk()
            ->json('data.messages');
        $this->assertSame([$first->id], array_column($filtered, 'id'));

        $this->asUser($this->buyer)
            ->getJson('/api/conversations/'.$this->seller->id.'/messages?listing_id=999999')
            ->assertOk()
            ->assertJsonPath('data.messages', []);

        $this->asUser($this->buyer)
            ->postJson('/api/conversations/'.$this->seller->id.'/read', [])
            ->assertOk()
            ->assertJsonPath('data.updated', 3);
        $this->assertNotNull($first->fresh()->read_at);
        $this->assertNotNull($second->fresh()->read_at);
        $this->assertNotNull($unlisted->fresh()->read_at);
        $this->assertNull($unrelated->fresh()->read_at);

        $incomingForBuyer = Message::create([
            'sender_id' => $this->seller->id,
            'receiver_id' => $this->buyer->id,
            'listing_id' => $firstListing->id,
            'body' => 'Incoming message',
        ]);
        $otherListingMessage = Message::create([
            'sender_id' => $this->seller->id,
            'receiver_id' => $this->buyer->id,
            'listing_id' => $secondListing->id,
            'body' => 'Message about the other listing',
        ]);
        $this->asUser($this->buyer)
            ->postJson('/api/conversations/'.$this->seller->id.'/read', [
                'listing_id' => $firstListing->id,
            ])
            ->assertOk()
            ->assertJsonPath('data.updated', 1);
        $this->assertNotNull($incomingForBuyer->fresh()->read_at);
        $this->assertNull($otherListingMessage->fresh()->read_at);

        $this->asUser($this->buyer)
            ->postJson('/api/conversations/'.$this->seller->id.'/read', [
                'listing_id' => 999999,
            ])
            ->assertOk()
            ->assertJsonPath('data.updated', 0);
    }

    #[Test]
    public function messaging_responses_and_errors_never_expose_participant_emails(): void
    {
        $listing = $this->createListing($this->seller);
        $created = $this->sendMessage($this->buyer, $this->seller, [
            'listing_id' => $listing->id,
        ])->assertCreated();
        $this->assertPrivateEmailsAbsent($created->getContent());

        $incoming = $this->sendMessage($this->seller, $this->buyer, [
            'listing_id' => $listing->id,
            'body' => 'A reply',
        ])->assertCreated();
        $this->assertPrivateEmailsAbsent($incoming->getContent());

        $conversations = $this->asUser($this->buyer)
            ->getJson('/api/conversations')
            ->assertOk();
        $this->assertPrivateEmailsAbsent($conversations->getContent());

        $thread = $this->asUser($this->buyer)
            ->getJson('/api/conversations/'.$this->seller->id.'/messages')
            ->assertOk();
        $this->assertPrivateEmailsAbsent($thread->getContent());

        $threadRead = $this->asUser($this->buyer)
            ->postJson('/api/conversations/'.$this->seller->id.'/read', [])
            ->assertOk();
        $this->assertPrivateEmailsAbsent($threadRead->getContent());

        $messageId = $incoming->json('data.id');
        $singleRead = $this->asUser($this->buyer)
            ->patchJson('/api/messages/'.$messageId.'/read')
            ->assertOk();
        $this->assertPrivateEmailsAbsent($singleRead->getContent());

        $validation = $this->sendMessage($this->buyer, $this->seller, [
            'sender_id' => $this->seller->id,
        ])->assertUnprocessable();
        $this->assertPrivateEmailsAbsent($validation->getContent());

        $notFound = $this->asUser($this->buyer)
            ->patchJson('/api/messages/999999/read')
            ->assertNotFound();
        $this->assertPrivateEmailsAbsent($notFound->getContent());

        $unauthenticated = $this->withoutHeader('Authorization')
            ->getJson('/api/conversations')
            ->assertUnauthorized();
        $this->assertPrivateEmailsAbsent($unauthenticated->getContent());

        $admin = User::factory()->admin()->create([
            'email' => 'admin@example.test',
        ]);
        $forbidden = $this->asUserWithAbility($admin, 'admin')
            ->getJson('/api/conversations')
            ->assertForbidden();
        $this->assertPrivateEmailsAbsent($forbidden->getContent());
    }

    private function assertPrivateEmailsAbsent(string $response): void
    {
        $this->assertStringNotContainsString($this->buyer->email, $response);
        $this->assertStringNotContainsString($this->seller->email, $response);
    }

    private function asUserWithAbility(User $user, string $ability): self
    {
        $this->app->make('auth')->forgetGuards();

        $token = $user->createToken('messaging-test', [$ability])->plainTextToken;

        return $this->withHeader('Authorization', 'Bearer '.$token);
    }
}
