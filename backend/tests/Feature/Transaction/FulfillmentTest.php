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
     * listing so cancellation tests start from a truthful available quantity.
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
    public function a_legacy_transaction_reserves_stock_when_completed(): void
    {
        $listing = $this->createListing(['quantity' => 1]);
        $transaction = $this->createTransaction($listing, 'farm_pickup', [
            'inventory_reserved' => false,
            'fulfillment_status' => FulfillmentStatus::PickedUp,
        ]);

        $this->assertSame(1, $listing->refresh()->quantity);

        $this->act($transaction, $this->buyer, 'complete')
            ->assertOk()
            ->assertJsonPath('data.status', 'completed');

        $this->assertSame(0, $listing->refresh()->quantity);
        $this->assertTrue((bool) $transaction->refresh()->inventory_reserved);

        // A second confirmation is a state conflict and cannot reserve again.
        $this->act($transaction, $this->buyer, 'complete')->assertStatus(409);
        $this->assertSame(0, $listing->refresh()->quantity);
    }

    #[Test]
    public function a_legacy_transaction_without_stock_cannot_complete(): void
    {
        $listing = $this->createListing(['quantity' => 0]);
        $transaction = $this->createTransaction($listing, 'farm_pickup', [
            'inventory_reserved' => false,
            'fulfillment_status' => FulfillmentStatus::PickedUp,
        ]);

        $this->act($transaction, $this->buyer, 'complete')->assertStatus(409);

        $this->assertSame(TransactionStatus::Pending, $transaction->refresh()->status);
        $this->assertFalse((bool) $transaction->refresh()->inventory_reserved);
        $this->assertSame(0, $listing->refresh()->quantity);
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
