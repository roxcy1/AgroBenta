<?php

namespace Tests\Feature\Transaction;

use App\Enums\FulfillmentStatus;
use App\Enums\ListingStatus;
use App\Enums\SellerCapability;
use App\Enums\TransactionStatus;
use App\Enums\UserRole;
use App\Models\Listing;
use App\Models\Transaction;
use App\Models\User;
use App\Notifications\TransactionCreated;
use App\Notifications\TransactionFulfillmentChanged;
use App\Notifications\TransactionStatusChanged;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Notification;
use Illuminate\Testing\TestResponse;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * The full transaction journey through the real HTTP API.
 *
 * This intentionally starts from an active listing and crosses the modules that
 * Phase 0–4 connected: Messaging -> Inquiry -> Offer -> reservation ->
 * fulfillment -> completion -> Admin reporting. It is the integration check the
 * focused unit/feature suites cannot provide on their own.
 */
class EndToEndTransactionFlowTest extends TestCase
{
    use RefreshDatabase;

    private User $buyer;

    private User $seller;

    private User $admin;

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

        $this->admin = User::factory()->create([
            'role' => UserRole::Admin,
            'seller_capability' => SellerCapability::Buyer,
        ]);
    }

    private function token(User $user, string $ability = 'mobile'): string
    {
        return $user->createToken($ability, [$ability])->plainTextToken;
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
            'quantity' => 2,
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

    private function asUser(User $user, string $method, string $uri, array $body = []): TestResponse
    {
        return $this->withHeader(
            'Authorization',
            'Bearer '.$this->token($user),
        )->json($method, $uri, $body);
    }

    /**
     * @return array<string, array{string, list<string>}>
     */
    public static function collectionFlows(): array
    {
        return [
            'personal pickup' => ['farm_pickup', [
                'preparing',
                'ready-for-pickup',
                'picked-up',
            ]],
            'buyer-arranged transportation' => ['buyer_arranged_transportation', [
                'preparing',
                'ready-for-pickup',
                'picked-up',
            ]],
            'seller-arranged delivery' => ['seller_arranged_delivery', [
                'preparing',
                'on-the-way',
                'delivered',
            ]],
        ];
    }

    #[Test]
    #[DataProvider('collectionFlows')]
    public function listing_to_completed_transaction_across_every_module(
        string $collectionMethod,
        array $sellerActions,
    ): void {
        Notification::fake();

        $listing = $this->createListing(['quantity' => 2]);

        // Ask Seller / Messages: a real buyer-seller thread must be reusable.
        $this->asUser($this->buyer, 'POST', '/api/messages', [
            'receiver_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'body' => 'Is this livestock still available?',
        ])->assertStatus(201);

        $this->asUser($this->seller, 'POST', '/api/messages', [
            'receiver_id' => $this->buyer->id,
            'listing_id' => $listing->id,
            'body' => 'Yes, it is available.',
        ])->assertStatus(201);

        $this->asUser($this->seller, 'GET', '/api/conversations')
            ->assertOk()
            ->assertJsonPath('data.conversations.0.counterpart.id', $this->buyer->id);

        // I'm Interested: the structured inquiry creates its message of record.
        $inquiry = $this->asUser($this->buyer, 'POST', '/api/inquiries', [
            'listing_id' => $listing->id,
            'message' => 'I would like to buy this animal.',
            'payment_method' => 'cash',
            'collection_method' => $collectionMethod,
        ])->assertStatus(201)->json('data');

        // Seller offer -> buyer acceptance -> atomic reservation.
        $offer = $this->asUser($this->seller, 'POST', '/api/offers', [
            'inquiry_id' => $inquiry['id'],
            'listing_id' => $listing->id,
            'proposed_amount' => '48000.00',
            'proposed_pickup_date' => now()->addDay()->toDateString(),
            'payment_method' => 'cash',
            'collection_method' => $collectionMethod,
        ])->assertStatus(201)->json('data');

        $accepted = $this->asUser(
            $this->buyer,
            'POST',
            '/api/offers/'.$offer['id'].'/accept',
        )->assertOk()->json('data');

        $transactionId = (int) $accepted['transaction']['id'];

        $this->assertDatabaseHas('transactions', [
            'id' => $transactionId,
            'status' => TransactionStatus::Pending->value,
            'fulfillment_status' => FulfillmentStatus::Confirmed->value,
            'inventory_reserved' => true,
        ]);
        $this->assertSame(1, $listing->refresh()->quantity);

        // Seller-controlled fulfillment progression.
        $expectedStages = [
            'preparing' => FulfillmentStatus::Preparing,
            'ready-for-pickup' => FulfillmentStatus::ReadyForPickup,
            'picked-up' => FulfillmentStatus::PickedUp,
            'on-the-way' => FulfillmentStatus::OnTheWay,
            'delivered' => FulfillmentStatus::Delivered,
        ];

        foreach ($sellerActions as $action) {
            $this->asUser(
                $this->seller,
                'POST',
                '/api/transactions/'.$transactionId.'/'.$action,
            )->assertOk()
                ->assertJsonPath(
                    'data.fulfillment_status',
                    $expectedStages[$action]->value,
                )
                ->assertJsonPath('data.status', 'pending');
        }

        // Buyer-only receipt confirmation completes the sale.
        $this->asUser($this->seller, 'GET', '/api/transactions/'.$transactionId)
            ->assertOk()
            ->assertJsonPath('data.permitted_actions', []);

        $this->asUser($this->buyer, 'GET', '/api/transactions/'.$transactionId)
            ->assertOk()
            ->assertJsonPath('data.permitted_actions', ['confirm_received']);

        $this->asUser(
            $this->buyer,
            'POST',
            '/api/transactions/'.$transactionId.'/complete',
        )->assertOk()
            ->assertJsonPath('data.status', 'completed')
            ->assertJsonPath('data.fulfillment_status', 'completed');

        $this->assertDatabaseHas('transactions', [
            'id' => $transactionId,
            'status' => TransactionStatus::Completed->value,
            'fulfillment_status' => FulfillmentStatus::Completed->value,
            'inventory_reserved' => true,
        ]);
        $this->assertSame(1, $listing->refresh()->quantity);

        Notification::assertSentTo($this->seller, TransactionCreated::class);
        Notification::assertSentTo($this->buyer, TransactionFulfillmentChanged::class);
        Notification::assertSentTo($this->seller, TransactionStatusChanged::class);

        // Admin reporting keeps the three unchanged transaction statuses and
        // sees the additive fulfillment field.
        $this->withHeader('Authorization', 'Bearer '.$this->token($this->admin, 'admin'))
            ->getJson('/api/admin/transactions?status=completed')
            ->assertOk()
            ->assertJsonPath('data.transactions.0.id', $transactionId)
            ->assertJsonPath('data.transactions.0.status', 'completed')
            ->assertJsonPath('data.transactions.0.fulfillment_status', 'completed');

        $this->withHeader('Authorization', 'Bearer '.$this->token($this->admin, 'admin'))
            ->getJson('/api/admin/reports')
            ->assertOk()
            ->assertJsonPath('data.transactions.completed', 1)
            ->assertJsonPath('data.transactions.pending', 0)
            ->assertJsonPath('data.transactions.total_revenue', 48000);
    }

    #[Test]
    public function offer_reservation_is_released_exactly_once_before_handover(): void
    {
        $listing = $this->createListing(['quantity' => 2]);

        $inquiry = $this->asUser($this->buyer, 'POST', '/api/inquiries', [
            'listing_id' => $listing->id,
            'message' => 'I am interested.',
            'payment_method' => 'cash',
            'collection_method' => 'farm_pickup',
        ])->assertStatus(201)->json('data');

        $offer = $this->asUser($this->seller, 'POST', '/api/offers', [
            'inquiry_id' => $inquiry['id'],
            'listing_id' => $listing->id,
            'proposed_amount' => '48000.00',
        ])->assertStatus(201)->json('data');

        $transactionId = $this->asUser(
            $this->buyer,
            'POST',
            '/api/offers/'.$offer['id'].'/accept',
        )->assertOk()->json('data.transaction.id');

        $this->assertSame(1, $listing->refresh()->quantity);

        $this->asUser(
            $this->buyer,
            'POST',
            '/api/transactions/'.$transactionId.'/cancel',
        )->assertOk()->assertJsonPath('data.status', 'cancelled');

        $this->assertSame(2, $listing->refresh()->quantity);
        $this->assertFalse((bool) Transaction::query()->findOrFail($transactionId)->inventory_reserved);

        $this->asUser(
            $this->buyer,
            'POST',
            '/api/transactions/'.$transactionId.'/cancel',
        )->assertStatus(409);

        $this->assertSame(2, $listing->refresh()->quantity);
    }

    #[Test]
    public function multi_quantity_offer_direct_sale_cancellation_and_sold_out_flow_preserves_inventory(): void
    {
        Notification::fake();

        $secondBuyer = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);
        $thirdBuyer = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);
        $listing = $this->createListing([
            'livestock_type' => 'goat',
            'breed' => 'Native',
            'quantity' => 5,
            'asking_price' => 2500.00,
            'short_description' => 'Five similar goats',
        ]);

        // Inquiries for different quantities are recorded without reserving stock.
        $firstInquiry = $this->asUser($this->buyer, 'POST', '/api/inquiries', [
            'listing_id' => $listing->id,
            'requested_quantity' => 2,
            'message' => 'I would like two goats.',
            'payment_method' => 'cash',
            'collection_method' => 'farm_pickup',
        ])->assertCreated()->json('data');
        $secondInquiry = $this->asUser($secondBuyer, 'POST', '/api/inquiries', [
            'listing_id' => $listing->id,
            'requested_quantity' => 1,
            'message' => 'I would like one goat.',
            'payment_method' => 'cash',
            'collection_method' => 'farm_pickup',
        ])->assertCreated()->json('data');
        $this->assertSame(5, $listing->refresh()->quantity);

        // Accepting a partial offer reserves only its agreed quantity and keeps
        // the offer's amount as the total agreed price.
        $firstOffer = $this->asUser($this->seller, 'POST', '/api/offers', [
            'inquiry_id' => $firstInquiry['id'],
            'listing_id' => $listing->id,
            'proposed_amount' => '4400.00',
            'proposed_quantity' => 2,
        ])->assertCreated()->json('data');
        $this->assertSame(2, $firstOffer['proposed_quantity']);
        $this->assertSame('4400.00', $firstOffer['proposed_amount']);

        $firstAcceptance = $this->asUser(
            $this->buyer,
            'POST',
            '/api/offers/'.$firstOffer['id'].'/accept',
        )->assertOk()->json('data');
        $firstTransactionId = (int) $firstAcceptance['transaction']['id'];
        $this->assertSame(2, (int) $firstAcceptance['transaction']['quantity']);
        $this->assertSame('4400.00', $firstAcceptance['transaction']['total_amount']);
        $this->assertSame(3, $listing->refresh()->quantity);

        $this->asUser($this->seller, 'POST', '/api/transactions/'.$firstTransactionId.'/preparing')->assertOk();
        $this->asUser($this->seller, 'POST', '/api/transactions/'.$firstTransactionId.'/ready-for-pickup')->assertOk();
        $this->asUser($this->seller, 'POST', '/api/transactions/'.$firstTransactionId.'/picked-up')->assertOk();
        $this->asUser($this->buyer, 'POST', '/api/transactions/'.$firstTransactionId.'/complete')
            ->assertOk()
            ->assertJsonPath('data.status', 'completed');
        $this->assertSame(3, $listing->refresh()->quantity);
        $this->asUser($this->buyer, 'GET', '/api/listings/'.$listing->id)
            ->assertOk()
            ->assertJsonPath('data.quantity', 3)
            ->assertJsonPath('data.platform_sold_quantity', 2)
            ->assertJsonPath('data.available_quantity', 3);

        // A second accepted offer can be cancelled before handover. Repeating
        // cancellation never restores the same head a second time.
        $secondOffer = $this->asUser($this->seller, 'POST', '/api/offers', [
            'inquiry_id' => $secondInquiry['id'],
            'listing_id' => $listing->id,
            'proposed_amount' => '2300.00',
            'proposed_quantity' => 1,
        ])->assertCreated()->json('data');
        $secondTransactionId = $this->asUser(
            $secondBuyer,
            'POST',
            '/api/offers/'.$secondOffer['id'].'/accept',
        )->assertOk()->json('data.transaction.id');
        $this->assertSame(2, $listing->refresh()->quantity);
        $this->asUser($secondBuyer, 'POST', '/api/transactions/'.$secondTransactionId.'/cancel')
            ->assertOk()
            ->assertJsonPath('data.status', 'cancelled');
        $this->assertSame(3, $listing->refresh()->quantity);
        $this->asUser($secondBuyer, 'POST', '/api/transactions/'.$secondTransactionId.'/cancel')
            ->assertStatus(409);
        $this->assertSame(3, $listing->refresh()->quantity);

        // The existing direct transaction endpoint shares the same reservation
        // path. Fully reserved inventory stays active but is absent from buyer
        // Marketplace and cannot receive another inquiry.
        $directTransaction = $this->asUser($secondBuyer, 'POST', '/api/transactions', [
            'listing_id' => $listing->id,
            'quantity' => 3,
        ])->assertCreated()
            ->assertJsonPath('data.quantity', 3)
            ->json('data');
        $this->assertSame(0, $listing->refresh()->quantity);
        $this->assertSame(ListingStatus::Active, $listing->status);
        $this->asUser($thirdBuyer, 'GET', '/api/listings')
            ->assertOk()
            ->assertJsonMissing(['id' => $listing->id]);
        $this->asUser($thirdBuyer, 'POST', '/api/inquiries', [
            'listing_id' => $listing->id,
            'requested_quantity' => 1,
            'message' => 'Is one still available?',
            'payment_method' => 'cash',
            'collection_method' => 'farm_pickup',
        ])->assertStatus(409);

        // Completing the remaining three heads sells out the listing; all three
        // transaction records remain preserved (completed, cancelled, completed).
        $directTransactionId = (int) $directTransaction['id'];
        $this->asUser($this->seller, 'POST', '/api/transactions/'.$directTransactionId.'/preparing')->assertOk();
        $this->asUser($this->seller, 'POST', '/api/transactions/'.$directTransactionId.'/ready-for-pickup')->assertOk();
        $this->asUser($this->seller, 'POST', '/api/transactions/'.$directTransactionId.'/picked-up')->assertOk();
        $this->asUser($secondBuyer, 'POST', '/api/transactions/'.$directTransactionId.'/complete')
            ->assertOk()
            ->assertJsonPath('data.status', 'completed');

        $this->assertSame(ListingStatus::Sold, $listing->refresh()->status);
        $this->assertSame(0, $listing->quantity);
        $this->assertSame(5, $listing->total_quantity);
        $this->withHeader('Authorization', 'Bearer '.$this->token($this->admin, 'admin'))
            ->getJson('/api/admin/listings/'.$listing->id)
            ->assertOk()
            ->assertJsonPath('data.platform_sold_quantity', 5)
            ->assertJsonPath('data.available_quantity', 0);
        $this->assertSame(3, Transaction::query()->where('listing_id', $listing->id)->count());
        $this->asUser($thirdBuyer, 'GET', '/api/listings/'.$listing->id)->assertNotFound();
    }
}
