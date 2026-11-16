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
use App\Notifications\TransactionFulfillmentChanged;
use App\Notifications\TransactionStatusChanged;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Notification;
use Illuminate\Testing\TestResponse;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * The fulfillment progression: pickup and seller-delivery flows, seller and
 * buyer authorization, cancellation cutoffs, legacy stock handling, and the
 * unchanged transaction status values.
 *
 * Transitions are sequential on purpose. The test suite should catch a broken
 * state machine as a 409, not as a silently skipped step.
 */
class FulfillmentTest extends TestCase
{
    use RefreshDatabase;

    private User $buyer;

    private User $seller;

    private User $stranger;

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

        $this->stranger = User::factory()->seller()->create([
            'role' => UserRole::User,
            'name' => 'Ramon Cruz',
        ]);

        $this->admin = User::factory()->create([
            'role' => UserRole::Admin,
            'seller_capability' => SellerCapability::Buyer,
        ]);
    }

    private function mobileToken(User $user): string
    {
        return $user->createToken('mobile', ['mobile'])->plainTextToken;
    }

    private function adminToken(): string
    {
        return $this->admin->createToken('admin', ['admin'])->plainTextToken;
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

    /**
     * A transaction already in the reservation model. The helper decrements the
     * listing so cancellation tests start from truthful available stock.
     */
    private function createTransaction(
        Listing $listing,
        ?string $collectionMethod,
        array $overrides = [],
    ): Transaction {
        $quantity = (int) ($overrides['quantity'] ?? 1);
        $reserved = (bool) ($overrides['inventory_reserved'] ?? true);

        if ($reserved) {
            Listing::query()->whereKey($listing->id)->decrement('quantity', $quantity);
        }

        return Transaction::create(array_merge([
            'buyer_id' => $this->buyer->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'quantity' => $quantity,
            'total_amount' => 50000.00 * $quantity,
            'collection_method' => $collectionMethod,
            'inventory_reserved' => $reserved,
            'inventory_accounted' => $reserved,
            'status' => TransactionStatus::Pending,
            'fulfillment_status' => FulfillmentStatus::Confirmed,
        ], $overrides));
    }

    private function act(Transaction $transaction, User $user, string $action): TestResponse
    {
        return $this->withHeader(
            'Authorization',
            'Bearer '.$this->mobileToken($user),
        )->postJson('/api/transactions/'.$transaction->id.'/'.$action);
    }

    /**
     * @return array<string, array{string|null}>
     */
    public static function pickupMethods(): array
    {
        return [
            'personal pickup' => ['farm_pickup'],
            'buyer arranged' => ['buyer_arranged_transportation'],
            'not sure yet' => ['not_sure_yet'],
            'legacy discuss' => ['discuss_with_seller'],
            'legacy null' => [null],
        ];
    }

    #[Test]
    #[DataProvider('pickupMethods')]
    public function pickup_flow_completes_after_buyer_confirmation(?string $method): void
    {
        Notification::fake();

        $listing = $this->createListing();
        $transaction = $this->createTransaction($listing, $method);

        $this->act($transaction, $this->seller, 'preparing')
            ->assertOk()
            ->assertJsonPath('data.fulfillment_status', 'preparing')
            ->assertJsonPath('data.status', 'pending');

        $this->act($transaction, $this->seller, 'ready-for-pickup')
            ->assertOk()
            ->assertJsonPath('data.fulfillment_status', 'ready_for_pickup');

        $this->act($transaction, $this->seller, 'picked-up')
            ->assertOk()
            ->assertJsonPath('data.fulfillment_status', 'picked_up');

        $this->act($transaction, $this->buyer, 'complete')
            ->assertOk()
            ->assertJsonPath('data.fulfillment_status', 'completed')
            ->assertJsonPath('data.status', 'completed');

        $this->assertDatabaseHas('transactions', [
            'id' => $transaction->id,
            'status' => TransactionStatus::Completed->value,
            'fulfillment_status' => FulfillmentStatus::Completed->value,
        ]);

        Notification::assertSentTo($this->buyer, TransactionFulfillmentChanged::class);
        Notification::assertSentTo($this->seller, TransactionStatusChanged::class);
    }

    #[Test]
    public function seller_arranged_delivery_uses_the_delivery_flow(): void
    {
        $listing = $this->createListing();
        $transaction = $this->createTransaction($listing, 'seller_arranged_delivery');

        $this->act($transaction, $this->seller, 'preparing')
            ->assertOk()
            ->assertJsonPath('data.fulfillment_status', 'preparing');

        $this->act($transaction, $this->seller, 'on-the-way')
            ->assertOk()
            ->assertJsonPath('data.fulfillment_status', 'on_the_way');

        $this->act($transaction, $this->seller, 'delivered')
            ->assertOk()
            ->assertJsonPath('data.fulfillment_status', 'delivered');

        $this->act($transaction, $this->buyer, 'complete')
            ->assertOk()
            ->assertJsonPath('data.status', 'completed')
            ->assertJsonPath('data.fulfillment_status', 'completed');
    }

    #[Test]
    public function pickup_actions_are_refused_on_a_delivery_flow(): void
    {
        $listing = $this->createListing();
        $transaction = $this->createTransaction($listing, 'seller_arranged_delivery');

        $this->act($transaction, $this->seller, 'preparing')->assertOk();
        $this->act($transaction, $this->seller, 'ready-for-pickup')->assertStatus(409);
        $this->act($transaction, $this->seller, 'picked-up')->assertStatus(409);

        $this->assertSame(
            FulfillmentStatus::Preparing,
            $transaction->refresh()->fulfillment_status,
        );
    }

    #[Test]
    public function delivery_actions_are_refused_on_a_pickup_flow(): void
    {
        $listing = $this->createListing();
        $transaction = $this->createTransaction($listing, 'farm_pickup');

        $this->act($transaction, $this->seller, 'preparing')->assertOk();
        $this->act($transaction, $this->seller, 'on-the-way')->assertStatus(409);
        $this->act($transaction, $this->seller, 'delivered')->assertStatus(409);

        $this->assertSame(
            FulfillmentStatus::Preparing,
            $transaction->refresh()->fulfillment_status,
        );
    }

    #[Test]
    public function an_out_of_order_step_is_refused(): void
    {
        $listing = $this->createListing();
        $transaction = $this->createTransaction($listing, 'farm_pickup');

        $this->act($transaction, $this->seller, 'ready-for-pickup')->assertStatus(409);
        $this->act($transaction, $this->seller, 'picked-up')->assertStatus(409);

        $this->assertSame(
            FulfillmentStatus::Confirmed,
            $transaction->refresh()->fulfillment_status,
        );
    }

    #[Test]
    public function the_buyer_cannot_use_seller_actions(): void
    {
        $listing = $this->createListing();
        $transaction = $this->createTransaction($listing, 'farm_pickup');

        // The route's seller capability gate refuses a buyer before the
        // service sees the request.
        $this->act($transaction, $this->buyer, 'preparing')->assertStatus(403);

        $this->assertSame(
            FulfillmentStatus::Confirmed,
            $transaction->refresh()->fulfillment_status,
        );
    }

    #[Test]
    public function the_seller_cannot_confirm_receipt(): void
    {
        $listing = $this->createListing();
        $transaction = $this->createTransaction($listing, 'farm_pickup', [
            'fulfillment_status' => FulfillmentStatus::PickedUp,
        ]);

        $this->act($transaction, $this->seller, 'complete')->assertStatus(409);

        $this->assertSame(
            TransactionStatus::Pending,
            $transaction->refresh()->status,
        );
    }

    #[Test]
    public function a_non_party_cannot_act_on_a_transaction(): void
    {
        $listing = $this->createListing();
        $transaction = $this->createTransaction($listing, 'farm_pickup');

        $this->act($transaction, $this->stranger, 'preparing')->assertStatus(404);
        $this->act($transaction, $this->stranger, 'complete')->assertStatus(404);
    }

    /**
     * @return array<string, array{FulfillmentStatus, bool}>
     */
    public static function pickupCancellationCutoff(): array
    {
        return [
            'confirmed' => [FulfillmentStatus::Confirmed, true],
            'preparing' => [FulfillmentStatus::Preparing, true],
            'ready for pickup' => [FulfillmentStatus::ReadyForPickup, true],
            'picked up' => [FulfillmentStatus::PickedUp, false],
        ];
    }

    #[Test]
    #[DataProvider('pickupCancellationCutoff')]
    public function pickup_cancellation_stops_at_handover(
        FulfillmentStatus $fulfillment,
        bool $allowed,
    ): void {
        $listing = $this->createListing();
        $transaction = $this->createTransaction($listing, 'farm_pickup', [
            'fulfillment_status' => $fulfillment,
        ]);

        $response = $this->act($transaction, $this->buyer, 'cancel');

        if ($allowed) {
            $response->assertOk()->assertJsonPath('data.status', 'cancelled');
            $this->assertSame(5, $listing->refresh()->quantity);
            $this->assertFalse((bool) $transaction->refresh()->inventory_reserved);
        } else {
            $response->assertStatus(409);
            $this->assertSame(4, $listing->refresh()->quantity);
            $this->assertTrue((bool) $transaction->refresh()->inventory_reserved);
            $this->assertSame(TransactionStatus::Pending, $transaction->refresh()->status);
        }
    }

    /**
     * @return array<string, array{FulfillmentStatus, bool}>
     */
    public static function deliveryCancellationCutoff(): array
    {
        return [
            'confirmed' => [FulfillmentStatus::Confirmed, true],
            'preparing' => [FulfillmentStatus::Preparing, true],
            'on the way' => [FulfillmentStatus::OnTheWay, false],
            'delivered' => [FulfillmentStatus::Delivered, false],
        ];
    }

    #[Test]
    #[DataProvider('deliveryCancellationCutoff')]
    public function delivery_cancellation_stops_at_dispatch(
        FulfillmentStatus $fulfillment,
        bool $allowed,
    ): void {
        $listing = $this->createListing();
        $transaction = $this->createTransaction($listing, 'seller_arranged_delivery', [
            'fulfillment_status' => $fulfillment,
        ]);

        $response = $this->act($transaction, $this->seller, 'cancel');

        if ($allowed) {
            $response->assertOk()->assertJsonPath('data.status', 'cancelled');
            $this->assertSame(5, $listing->refresh()->quantity);
        } else {
            $response->assertStatus(409);
            $this->assertSame(4, $listing->refresh()->quantity);
            $this->assertSame(TransactionStatus::Pending, $transaction->refresh()->status);
        }
    }

    #[Test]
    public function completing_a_legacy_unaccounted_transaction_does_not_adjust_stock(): void
    {
        $listing = $this->createListing(['quantity' => 1]);
        $listing->forceFill([
            'total_quantity' => null,
            'inventory_reconciliation_required' => true,
            'legacy_quantity_snapshot' => 1,
        ])->save();
        $transaction = $this->createTransaction($listing, 'farm_pickup', [
            'inventory_reserved' => false,
            'inventory_accounted' => false,
            'fulfillment_status' => FulfillmentStatus::PickedUp,
        ]);

        $this->assertSame(1, $listing->refresh()->quantity);

        $this->act($transaction, $this->buyer, 'complete')
            ->assertOk()
            ->assertJsonPath('data.status', 'completed');

        $this->assertSame(1, $listing->refresh()->quantity);
        $this->assertFalse((bool) $transaction->refresh()->inventory_reserved);
        $this->assertFalse((bool) $transaction->inventory_accounted);
        $this->assertTrue((bool) $listing->inventory_reconciliation_required);

        // A second confirmation is a state conflict and cannot adjust stock.
        $this->act($transaction, $this->buyer, 'complete')->assertStatus(409);
        $this->assertSame(1, $listing->refresh()->quantity);
    }

    #[Test]
    public function a_legacy_pending_transaction_can_complete_without_fabricating_a_reservation(): void
    {
        $listing = $this->createListing(['quantity' => 0]);
        $listing->forceFill([
            'total_quantity' => null,
            'inventory_reconciliation_required' => true,
            'legacy_quantity_snapshot' => 0,
        ])->save();
        $transaction = $this->createTransaction($listing, 'farm_pickup', [
            'inventory_reserved' => false,
            'inventory_accounted' => false,
            'fulfillment_status' => FulfillmentStatus::PickedUp,
        ]);

        $this->act($transaction, $this->buyer, 'complete')
            ->assertOk()
            ->assertJsonPath('data.status', 'completed');

        $this->assertSame(TransactionStatus::Completed, $transaction->refresh()->status);
        $this->assertFalse((bool) $transaction->refresh()->inventory_reserved);
        $this->assertFalse((bool) $transaction->inventory_accounted);
        $this->assertSame(0, $listing->refresh()->quantity);
    }

    #[Test]
    public function partial_completion_moves_reserved_heads_to_sold_and_keeps_the_listing_available(): void
    {
        $listing = $this->createListing(['quantity' => 5]);
        $transaction = $this->createTransaction($listing, 'farm_pickup', [
            'quantity' => 2,
            'fulfillment_status' => FulfillmentStatus::PickedUp,
        ]);

        $this->act($transaction, $this->buyer, 'complete')->assertOk();

        $listingResponse = $this->withHeader(
            'Authorization',
            'Bearer '.$this->mobileToken($this->buyer),
        )->getJson('/api/listings/'.$listing->id)->assertOk();

        $listingResponse
            ->assertJsonPath('data.total_quantity', 5)
            ->assertJsonPath('data.reserved_quantity', 0)
            ->assertJsonPath('data.sold_quantity', 2)
            ->assertJsonPath('data.available_quantity', 3)
            ->assertJsonPath('data.quantity', 3)
            ->assertJsonPath('data.status', ListingStatus::Active->value);
    }

    #[Test]
    public function completing_the_last_animal_marks_the_listing_sold_exactly_once(): void
    {
        $listing = $this->createListing(['quantity' => 3]);
        $first = $this->createTransaction($listing, 'farm_pickup', [
            'quantity' => 2,
            'fulfillment_status' => FulfillmentStatus::PickedUp,
        ]);
        $last = $this->createTransaction($listing, 'farm_pickup', [
            'quantity' => 1,
            'fulfillment_status' => FulfillmentStatus::PickedUp,
        ]);

        $this->act($first, $this->buyer, 'complete')->assertOk();
        $this->assertSame(ListingStatus::Active, $listing->refresh()->status);
        $this->assertSame(0, (int) $listing->quantity);

        $this->act($last, $this->buyer, 'complete')->assertOk();
        $this->assertSame(ListingStatus::Sold, $listing->refresh()->status);
        $this->assertSame(0, (int) $listing->quantity);
        $this->assertSame(3, (int) $listing->total_quantity);

        $this->act($last, $this->buyer, 'complete')->assertStatus(409);
        $this->assertSame(ListingStatus::Sold, $listing->refresh()->status);
    }

    #[Test]
    public function repeated_actions_are_refused_without_side_effects(): void
    {
        $listing = $this->createListing();
        $transaction = $this->createTransaction($listing, 'farm_pickup');

        $this->act($transaction, $this->seller, 'preparing')->assertOk();
        $this->act($transaction, $this->seller, 'preparing')->assertStatus(409);

        $this->act($transaction, $this->seller, 'ready-for-pickup')->assertOk();
        $this->act($transaction, $this->seller, 'picked-up')->assertOk();

        $this->act($transaction, $this->buyer, 'complete')->assertOk();
        $this->act($transaction, $this->buyer, 'complete')->assertStatus(409);

        // The reservation was taken at creation and is consumed once.
        $this->assertSame(4, $listing->refresh()->quantity);
        $this->assertSame(
            TransactionStatus::Completed,
            $transaction->refresh()->status,
        );
    }

    #[Test]
    public function permitted_actions_are_viewer_specific(): void
    {
        $listing = $this->createListing();
        $transaction = $this->createTransaction($listing, 'farm_pickup');

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->buyer))
            ->getJson('/api/transactions/'.$transaction->id)
            ->assertOk()
            ->assertJsonPath('data.fulfillment_status', 'confirmed')
            ->assertJsonPath('data.permitted_actions', ['cancel']);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->getJson('/api/transactions/'.$transaction->id)
            ->assertOk()
            ->assertJsonPath('data.permitted_actions', ['preparing', 'cancel']);
    }

    #[Test]
    public function admin_sees_fulfillment_without_a_new_transaction_status(): void
    {
        $listing = $this->createListing();
        $transaction = $this->createTransaction($listing, 'farm_pickup');

        $this->act($transaction, $this->seller, 'preparing');
        $this->act($transaction, $this->seller, 'ready-for-pickup');
        $this->act($transaction, $this->seller, 'picked-up');
        $this->act($transaction, $this->buyer, 'complete');

        $this->withHeader('Authorization', 'Bearer '.$this->adminToken())
            ->getJson('/api/admin/transactions?status=completed')
            ->assertOk()
            ->assertJsonPath('data.transactions.0.id', $transaction->id)
            ->assertJsonPath('data.transactions.0.status', 'completed')
            ->assertJsonPath('data.transactions.0.fulfillment_status', 'completed');

        $this->withHeader('Authorization', 'Bearer '.$this->adminToken())
            ->getJson('/api/admin/reports')
            ->assertOk()
            ->assertJsonPath('data.transactions.completed', 1)
            ->assertJsonPath('data.transactions.pending', 0);
    }
}
