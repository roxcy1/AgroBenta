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
}
