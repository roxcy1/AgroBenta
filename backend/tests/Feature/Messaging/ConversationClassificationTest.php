<?php

namespace Tests\Feature\Messaging;

use App\Enums\ListingStatus;
use App\Enums\TransactionStatus;
use App\Enums\UserRole;
use App\Models\Inquiry;
use App\Models\Listing;
use App\Models\Message;
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
        $this->assertSame($chatListing->id, $conversations[0]['listing_id']);
        $this->assertTrue($conversations[0]['has_inquiry']);
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
}
