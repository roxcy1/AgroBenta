<?php

namespace Tests\Feature\Messaging;

use App\Enums\ListingStatus;
use App\Enums\OfferStatus;
use App\Enums\TransactionStatus;
use App\Enums\UserRole;
use App\Models\Inquiry;
use App\Models\Listing;
use App\Models\Message;
use App\Models\Offer;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * The inbox's All filter lists every counterpart the caller has an inquiry,
 * offer or transaction with, even when no message exists between them yet.
 *
 * A transaction (and an offer) never writes a message, and an older inquiry
 * may predate the inquiry-as-message change, so a list built only from the
 * messages table left those people out of All while the Inquiries and
 * Transactions filters showed them (Trello "Kompanya": MESSAGES — "All" tab
 * does not list a person who has an inquiry or a transaction but no chat
 * message).
 */
class ConversationWithoutMessagesTest extends TestCase
{
    use RefreshDatabase;

    private User $buyer;

    private User $seller;

    private User $stranger;

    protected function setUp(): void
    {
        parent::setUp();

        $this->buyer = User::factory()->create([
            'role' => UserRole::User,
            'name' => 'Pedro Reyes',
        ]);

        $this->seller = User::factory()->seller()->create([
            'role' => UserRole::User,
            'name' => 'Juan Dela Cruz',
        ]);

        $this->stranger = User::factory()->create([
            'role' => UserRole::User,
            'name' => 'Maria Santos',
        ]);
    }

    private function mobileToken(User $user): string
    {
        return $user->createToken('mobile', ['mobile'])->plainTextToken;
    }

    private function createListing(User $seller, array $overrides = []): Listing
    {
        return Listing::create(array_merge([
            'seller_id' => $seller->id,
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
     * @return array<int, array<string, mixed>>
     */
    private function conversations(User $user): array
    {
        return $this->withHeader(
            'Authorization',
            'Bearer '.$this->mobileToken($user),
        )->getJson('/api/conversations')
            ->assertStatus(200)
            ->json('data.conversations');
    }

    #[Test]
    public function a_transaction_without_messages_is_listed_for_both_parties(): void
    {
        $listing = $this->createListing($this->seller);
        $this->createTransaction($this->buyer, $this->seller, $listing);

        $buyerView = $this->conversations($this->buyer);
        $this->assertCount(1, $buyerView);
        $this->assertSame($this->seller->id, $buyerView[0]['counterpart']['id']);
        $this->assertSame('Juan Dela Cruz', $buyerView[0]['counterpart']['name']);
        $this->assertSame('Transaction started', $buyerView[0]['last_message']);
        $this->assertNotNull($buyerView[0]['last_message_at']);
        $this->assertSame(0, $buyerView[0]['unread_count']);
        $this->assertTrue($buyerView[0]['has_transaction']);
        $this->assertFalse($buyerView[0]['has_inquiry']);
        $this->assertSame(['buyer'], $buyerView[0]['roles']);
        $this->assertSame($listing->id, $buyerView[0]['listing_id']);
        $this->assertSame('Angus', $buyerView[0]['listing_title']);
        $this->assertSame(1, $buyerView[0]['listing_count']);

        $sellerView = $this->conversations($this->seller);
        $this->assertCount(1, $sellerView);
        $this->assertSame($this->buyer->id, $sellerView[0]['counterpart']['id']);
        $this->assertSame(['seller'], $sellerView[0]['roles']);

        $this->assertDatabaseCount('messages', 0);
    }

    #[Test]
    public function an_inquiry_without_messages_is_listed(): void
    {
        $listing = $this->createListing($this->seller);
        $this->createInquiry($this->buyer, $this->seller, $listing);

        $sellerView = $this->conversations($this->seller);

        $this->assertCount(1, $sellerView);
        $this->assertSame($this->buyer->id, $sellerView[0]['counterpart']['id']);
        $this->assertSame('Inquiry sent', $sellerView[0]['last_message']);
        $this->assertTrue($sellerView[0]['has_inquiry']);
        $this->assertFalse($sellerView[0]['has_transaction']);
        // The seller can still start an offer from the chat.
        $this->assertNotNull($sellerView[0]['eligible_inquiry']);
    }

    #[Test]
    public function the_latest_activity_names_the_placeholder(): void
    {
        $listing = $this->createListing($this->seller);
        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing);

        $this->travel(1)->hours();
        Offer::create([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'seller_id' => $this->seller->id,
            'buyer_id' => $this->buyer->id,
            'proposed_amount' => 47500.00,
            'status' => OfferStatus::Accepted,
        ]);

        $this->assertSame('Offer sent', $this->conversations($this->buyer)[0]['last_message']);

        $this->travel(1)->hours();
        $this->createTransaction($this->buyer, $this->seller, $listing);

        $buyerView = $this->conversations($this->buyer);
        $this->assertCount(1, $buyerView);
        $this->assertSame('Transaction started', $buyerView[0]['last_message']);
        $this->assertTrue($buyerView[0]['has_inquiry']);
        $this->assertTrue($buyerView[0]['has_transaction']);
        $this->assertSame('accepted', $buyerView[0]['latest_offer']['status']);
    }

    #[Test]
    public function a_counterpart_with_messages_is_not_listed_twice(): void
    {
        $listing = $this->createListing($this->seller);
        $this->createTransaction($this->buyer, $this->seller, $listing);
        Message::create([
            'sender_id' => $this->seller->id,
            'receiver_id' => $this->buyer->id,
            'listing_id' => $listing->id,
            'body' => 'Ready for pickup on Saturday.',
        ]);

        $buyerView = $this->conversations($this->buyer);

        $this->assertCount(1, $buyerView);
        $this->assertSame('Ready for pickup on Saturday.', $buyerView[0]['last_message']);
        $this->assertSame(1, $buyerView[0]['unread_count']);
        $this->assertTrue($buyerView[0]['has_transaction']);
    }

    #[Test]
    public function rows_are_ordered_by_latest_activity(): void
    {
        $otherSeller = User::factory()->seller()->create([
            'role' => UserRole::User,
            'name' => 'Ramon Cruz',
        ]);

        Message::create([
            'sender_id' => $otherSeller->id,
            'receiver_id' => $this->buyer->id,
            'listing_id' => null,
            'body' => 'Hello',
        ]);

        $this->travel(1)->hours();
        $this->createTransaction($this->buyer, $this->seller, $this->createListing($this->seller));

        $ids = array_column(
            array_column($this->conversations($this->buyer), 'counterpart'),
            'id',
        );

        $this->assertSame([$this->seller->id, $otherSeller->id], $ids);
    }

    #[Test]
    public function a_user_never_sees_other_peoples_counterparts(): void
    {
        $listing = $this->createListing($this->seller);
        $this->createInquiry($this->buyer, $this->seller, $listing);
        $this->createTransaction($this->buyer, $this->seller, $listing);

        $this->assertSame([], $this->conversations($this->stranger));
    }

    #[Test]
    public function the_first_message_starts_the_real_conversation(): void
    {
        $listing = $this->createListing($this->seller);
        $this->createTransaction($this->buyer, $this->seller, $listing);

        $token = 'Bearer '.$this->mobileToken($this->buyer);

        // Opening the row loads an empty thread...
        $this->withHeader('Authorization', $token)
            ->getJson("/api/conversations/{$this->seller->id}/messages")
            ->assertOk()
            ->assertJsonCount(0, 'data.messages');

        // ...and the composer sends the way it always does.
        $this->withHeader('Authorization', $token)
            ->postJson('/api/messages', [
                'receiver_id' => $this->seller->id,
                'listing_id' => $listing->id,
                'body' => 'When can I pick it up?',
            ])
            ->assertStatus(201);

        $buyerView = $this->conversations($this->buyer);
        $this->assertCount(1, $buyerView);
        $this->assertSame('When can I pick it up?', $buyerView[0]['last_message']);
        $this->assertTrue($buyerView[0]['has_transaction']);
    }
}
