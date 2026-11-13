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
 * The conversation list's inquiry/transaction classification.
 *
 * `GET /api/conversations` is the only read surface the inbox has, and the
 * Inquiries/Transactions filter chips must not be populated with fake data.
 * These tests pin the classification to the buyer–seller pair: a conversation
 * is the counterpart pair, so an inquiry or transaction between those two
 * users is what the filters select, regardless of which listing the latest
 * message mentions.
 */
class ConversationClassificationTest extends TestCase
{
    use RefreshDatabase;

    private User $buyer;

    private User $seller;

    private User $otherSeller;

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

        $this->otherSeller = User::factory()->seller()->create([
            'role' => UserRole::User,
            'name' => 'Ramon Cruz',
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

    private function sendMessage(User $sender, User $receiver, ?int $listingId = null): Message
    {
        return Message::create([
            'sender_id' => $sender->id,
            'receiver_id' => $receiver->id,
            'listing_id' => $listingId,
            'body' => 'Hello',
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
    public function a_conversation_with_an_inquiry_is_classified_as_an_inquiry(): void
    {
        $listing = $this->createListing($this->seller);
        $this->createInquiry($this->buyer, $this->seller, $listing);
        $this->sendMessage($this->buyer, $this->seller, $listing->id);

        $conversations = $this->conversations($this->buyer);

        $this->assertCount(1, $conversations);
        $this->assertTrue($conversations[0]['has_inquiry']);
        $this->assertFalse($conversations[0]['has_transaction']);
    }

    #[Test]
    public function a_conversation_with_a_transaction_is_classified_as_a_transaction(): void
    {
        $listing = $this->createListing($this->seller);
        $this->sendMessage($this->buyer, $this->seller, $listing->id);

        Transaction::create([
            'buyer_id' => $this->buyer->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'quantity' => 1,
            'total_amount' => 48000.00,
            'status' => TransactionStatus::Pending,
        ]);

        $conversations = $this->conversations($this->buyer);

        $this->assertCount(1, $conversations);
        $this->assertFalse($conversations[0]['has_inquiry']);
        $this->assertTrue($conversations[0]['has_transaction']);
    }

    #[Test]
    public function classification_is_by_counterpart_not_by_listing(): void
    {
        $inquiryListing = $this->createListing($this->seller);
        $this->createInquiry($this->buyer, $this->seller, $inquiryListing);

        // The latest message mentions a different listing from the same pair.
        $chatListing = $this->createListing($this->seller, [
            'livestock_type' => 'goat',
            'breed' => 'Boer',
        ]);
        $this->sendMessage($this->buyer, $this->seller, $chatListing->id);

        $conversations = $this->conversations($this->buyer);

        $this->assertCount(1, $conversations);
        $this->assertSame(
            $inquiryListing->id,
            $conversations[0]['listing_id'],
            'the open inquiry names the listing the preview should show',
        );
        $this->assertTrue($conversations[0]['has_inquiry']);
        $this->assertSame(2, $conversations[0]['listing_count']);
    }

    #[Test]
    public function a_plain_chat_is_classified_as_neither(): void
    {
        $listing = $this->createListing($this->otherSeller);
        $this->sendMessage($this->buyer, $this->otherSeller, $listing->id);

        $conversations = $this->conversations($this->buyer);

        $this->assertCount(1, $conversations);
        $this->assertFalse($conversations[0]['has_inquiry']);
        $this->assertFalse($conversations[0]['has_transaction']);
    }

    #[Test]
    public function a_seller_sees_the_same_classification_for_the_pair(): void
    {
        $listing = $this->createListing($this->seller);
        $this->createInquiry($this->buyer, $this->seller, $listing);
        $this->sendMessage($this->seller, $this->buyer, $listing->id);

        $conversations = $this->conversations($this->seller);

        $this->assertCount(1, $conversations);
        $this->assertSame($this->buyer->id, $conversations[0]['counterpart']['id']);
        $this->assertTrue($conversations[0]['has_inquiry']);
        $this->assertFalse($conversations[0]['has_transaction']);
    }

    #[Test]
    public function roles_name_the_callers_side_of_the_pair(): void
    {
        $listing = $this->createListing($this->seller);
        $this->createInquiry($this->buyer, $this->seller, $listing);
        $this->sendMessage($this->buyer, $this->seller, $listing->id);

        $this->assertSame(['buyer'], $this->conversations($this->buyer)[0]['roles']);
        $this->assertSame(['seller'], $this->conversations($this->seller)[0]['roles']);
    }

    #[Test]
    public function a_pair_that_trades_both_ways_has_both_roles(): void
    {
        $sellerListing = $this->createListing($this->seller);
        $this->createInquiry($this->buyer, $this->seller, $sellerListing);
        $this->sendMessage($this->buyer, $this->seller, $sellerListing->id);

        // The buyer is a seller too, and the other party bought from them.
        $buyerListing = $this->createListing($this->buyer, [
            'livestock_type' => 'goat',
            'breed' => 'Boer',
        ]);
        $this->sendMessage($this->seller, $this->buyer, $buyerListing->id);

        $this->assertSame(
            ['buyer', 'seller'],
            $this->conversations($this->buyer)[0]['roles'],
        );
        $this->assertSame(
            ['buyer', 'seller'],
            $this->conversations($this->seller)[0]['roles'],
        );
    }

    #[Test]
    public function a_thread_with_no_relatable_record_has_no_roles(): void
    {
        // No listing, no inquiry, no transaction, no offer: the app must show
        // this in both modes rather than hide the message history.
        $this->sendMessage($this->buyer, $this->otherSeller);

        $conversation = $this->conversations($this->buyer)[0];

        $this->assertSame([], $conversation['roles']);
        $this->assertSame(0, $conversation['listing_count']);
        $this->assertNull($conversation['latest_offer']);
        $this->assertNull($conversation['eligible_inquiry']);
    }

    #[Test]
    public function only_the_seller_receives_the_eligible_inquiry(): void
    {
        $listing = $this->createListing($this->seller);
        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing);
        $this->sendMessage($this->buyer, $this->seller, $listing->id);

        $sellerView = $this->conversations($this->seller)[0];
        $this->assertSame($inquiry->id, $sellerView['eligible_inquiry']['id']);
        $this->assertSame($listing->id, $sellerView['eligible_inquiry']['listing_id']);
        $this->assertSame('Angus', $sellerView['eligible_inquiry']['listing_title']);

        $this->assertNull($this->conversations($this->buyer)[0]['eligible_inquiry']);
    }

    #[Test]
    public function the_latest_offer_is_part_of_the_preview_and_blocks_a_second_one(): void
    {
        $listing = $this->createListing($this->seller);
        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing);
        $this->sendMessage($this->buyer, $this->seller, $listing->id);

        Offer::create([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'seller_id' => $this->seller->id,
            'buyer_id' => $this->buyer->id,
            'proposed_amount' => 47500.00,
            'status' => OfferStatus::Pending,
        ]);

        $sellerView = $this->conversations($this->seller)[0];
        $this->assertSame('pending', $sellerView['latest_offer']['status']);
        $this->assertSame('47500.00', $sellerView['latest_offer']['proposed_amount']);
        $this->assertSame($listing->id, $sellerView['latest_offer']['listing_id']);
        $this->assertSame('Angus', $sellerView['latest_offer']['listing_title']);
        $this->assertSame(['seller'], $sellerView['roles']);
        $this->assertNull(
            $sellerView['eligible_inquiry'],
            'a pending offer already answers this inquiry',
        );

        $buyerView = $this->conversations($this->buyer)[0];
        $this->assertSame('pending', $buyerView['latest_offer']['status']);
        $this->assertSame(['buyer'], $buyerView['roles']);
    }

    #[Test]
    public function listing_count_counts_every_listing_discussed_in_the_thread(): void
    {
        $first = $this->createListing($this->seller);
        $second = $this->createListing($this->seller, [
            'livestock_type' => 'goat',
            'breed' => 'Boer',
        ]);

        $this->sendMessage($this->buyer, $this->seller, $first->id);
        $this->sendMessage($this->buyer, $this->seller, $second->id);

        $conversation = $this->conversations($this->buyer)[0];

        $this->assertCount(1, $this->conversations($this->buyer));
        $this->assertSame(2, $conversation['listing_count']);
        $this->assertSame($second->id, $conversation['listing_id']);
    }

    #[Test]
    public function the_preview_prefers_the_listing_with_the_pending_offer(): void
    {
        $messageListing = $this->createListing($this->seller);
        $offerListing = $this->createListing($this->seller, [
            'livestock_type' => 'goat',
            'breed' => 'Boer',
            'asking_price' => 42000.00,
        ]);

        // The newest message is about one listing; the offer is about another.
        $this->sendMessage($this->buyer, $this->seller, $messageListing->id);

        $inquiry = $this->createInquiry($this->buyer, $this->seller, $offerListing);
        Offer::create([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $offerListing->id,
            'seller_id' => $this->seller->id,
            'buyer_id' => $this->buyer->id,
            'proposed_amount' => 40000.00,
            'status' => OfferStatus::Pending,
        ]);

        $conversation = $this->conversations($this->buyer)[0];

        $this->assertSame($offerListing->id, $conversation['listing_id']);
        $this->assertSame('Boer', $conversation['listing_title']);
        $this->assertSame('42000.00', (string) $conversation['listing_price']);
        $this->assertSame(2, $conversation['listing_count']);
        $this->assertSame('pending', $conversation['latest_offer']['status']);
    }

    #[Test]
    public function an_accepted_inquiry_is_no_longer_eligible_in_chat(): void
    {
        $listing = $this->createListing($this->seller);
        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing);
        $this->sendMessage($this->buyer, $this->seller, $listing->id);

        Offer::create([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'seller_id' => $this->seller->id,
            'buyer_id' => $this->buyer->id,
            'proposed_amount' => 47000.00,
            'status' => OfferStatus::Accepted,
        ]);

        $sellerView = $this->conversations($this->seller)[0];

        $this->assertSame(['seller'], $sellerView['roles']);
        $this->assertNull(
            $sellerView['eligible_inquiry'],
            'acceptance is permanent: the seller may never offer again',
        );
    }

    #[Test]
    public function a_users_own_messages_are_never_counted_as_unread(): void
    {
        $listing = $this->createListing($this->seller);

        $this->sendMessage($this->seller, $this->buyer, $listing->id);
        $this->sendMessage($this->seller, $this->buyer, $listing->id);
        $this->sendMessage($this->buyer, $this->seller, $listing->id);

        $buyerView = $this->conversations($this->buyer)[0];
        $sellerView = $this->conversations($this->seller)[0];

        $this->assertSame(2, $buyerView['unread_count']);
        $this->assertSame(1, $sellerView['unread_count']);
    }
}
