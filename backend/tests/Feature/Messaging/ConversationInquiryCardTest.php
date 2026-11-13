<?php

namespace Tests\Feature\Messaging;

use App\Enums\ListingStatus;
use App\Enums\UserRole;
use App\Models\Inquiry;
use App\Models\Listing;
use App\Models\Message;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * The structured inquiry card the chat renders instead of the generated body.
 *
 * The backend attaches an `inquiry` payload to the one message that opened an
 * inquiry, so the client never re-parses prose and never shows the same card
 * twice when a conversation covers several listings.
 */
class ConversationInquiryCardTest extends TestCase
{
    use RefreshDatabase;

    private User $buyer;

    private User $seller;

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
    }

    private function mobileToken(User $user): string
    {
        return $user->createToken('mobile', ['mobile'])->plainTextToken;
    }

    private function createListing(array $overrides = []): Listing
    {
        return Listing::create(array_merge([
            'seller_id' => $this->seller->id,
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

    private function createInquiry(Listing $listing, array $overrides = []): Inquiry
    {
        return Inquiry::create(array_merge([
            'buyer_id' => $this->buyer->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'subject' => 'Is this still available?',
            'message' => 'I would like to buy this animal.',
            'status' => 'open',
            'payment_method' => 'gcash',
            'collection_method' => 'farm_pickup',
            'preferred_schedule' => now()->addDays(2)->toDateString(),
        ], $overrides));
    }

    private function sendInquiryMessage(Listing $listing): Message
    {
        return Message::create([
            'sender_id' => $this->buyer->id,
            'receiver_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'body' => 'New inquiry from Pedro Reyes.',
        ]);
    }

    /**
     * @return array<int, array<string, mixed>>
     */
    private function thread(User $user, int $counterpartId): array
    {
        return $this->withHeader(
            'Authorization',
            'Bearer '.$this->mobileToken($user),
        )->getJson('/api/conversations/'.$counterpartId.'/messages')
            ->assertOk()
            ->json('data.messages');
    }

    #[Test]
    public function the_inquiry_opening_message_carries_a_structured_card(): void
    {
        $listing = $this->createListing();
        $inquiry = $this->createInquiry($listing);
        $this->sendInquiryMessage($listing);

        $messages = $this->thread($this->seller, $this->buyer->id);

        $this->assertCount(1, $messages);
        $card = $messages[0]['inquiry'];

        $this->assertSame($inquiry->id, $card['id']);
        $this->assertSame($listing->id, $card['listing']['id']);
        $this->assertSame('cattle Angus', $card['listing']['title']);
        $this->assertSame('50000.00', (string) $card['listing']['asking_price']);
        $this->assertSame('gcash', $card['payment_method']);
        $this->assertSame('farm_pickup', $card['collection_method']);
        $this->assertSame(
            now()->addDays(2)->toDateString(),
            $card['preferred_schedule'],
        );
        $this->assertSame('I would like to buy this animal.', $card['message']);
    }

    #[Test]
    public function a_plain_message_has_no_card(): void
    {
        $listing = $this->createListing();
        $this->createInquiry($listing);
        $this->sendInquiryMessage($listing);
        Message::create([
            'sender_id' => $this->seller->id,
            'receiver_id' => $this->buyer->id,
            'listing_id' => $listing->id,
            'body' => 'Yes, still available.',
        ]);

        $messages = $this->thread($this->buyer, $this->seller->id);

        $reply = null;
        $opener = null;
        foreach ($messages as $message) {
            if ((int) $message['sender_id'] === $this->seller->id) {
                $reply = $message;
            }
            if ((int) $message['sender_id'] === $this->buyer->id) {
                $opener = $message;
            }
        }

        $this->assertNotNull($reply);
        $this->assertNull($reply['inquiry'], 'the reply is a normal bubble');
        $this->assertNotNull($opener);
        $this->assertNotNull($opener['inquiry'], 'only the opener has the card');
    }

    #[Test]
    public function a_listing_with_photos_does_not_break_the_inquiry_payloads(): void
    {
        // Regression: `reset()` on the overloaded `$listing->photos` property
        // raised "Indirect modification of overloaded property" and turned the
        // whole inbox/thread response into a 500 whenever a listing had photos.
        $listing = $this->createListing(['photos' => ['heifer.jpg']]);
        $this->createInquiry($listing);
        $this->sendInquiryMessage($listing);

        $messages = $this->thread($this->seller, $this->buyer->id);

        $photo = $messages[0]['inquiry']['listing']['photo_url'];
        $this->assertIsString($photo);
        $this->assertStringContainsString('heifer.jpg', $photo);

        $conversations = $this->withHeader(
            'Authorization',
            'Bearer '.$this->mobileToken($this->seller),
        )->getJson('/api/conversations')
            ->assertOk()
            ->json('data.conversations');

        $this->assertStringContainsString(
            'heifer.jpg',
            $conversations[0]['eligible_inquiry']['listing_photo_url'],
        );
    }

    #[Test]
    public function two_inquiries_on_different_listings_each_get_one_card(): void
    {
        $first = $this->createListing();
        $second = $this->createListing([
            'livestock_type' => 'goat',
            'breed' => 'Boer',
            'asking_price' => 18000.00,
        ]);

        $firstInquiry = $this->createInquiry($first);
        $this->sendInquiryMessage($first);
        $secondInquiry = $this->createInquiry($second);
        $this->sendInquiryMessage($second);

        $messages = $this->thread($this->seller, $this->buyer->id);
        $cards = array_values(array_filter(
            array_column($messages, 'inquiry'),
            fn ($card): bool => $card !== null,
        ));

        $this->assertCount(2, $cards, 'one card per inquiry, never duplicated');
        $this->assertSame(
            [$firstInquiry->id, $secondInquiry->id],
            array_column($cards, 'id'),
        );
        $this->assertSame(
            ['cattle Angus', 'goat Boer'],
            array_column(array_column($cards, 'listing'), 'title'),
        );
    }
}
