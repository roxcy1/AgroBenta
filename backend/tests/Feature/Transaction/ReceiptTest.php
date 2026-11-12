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
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Notification;
use Illuminate\Testing\TestResponse;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * The completed-sale receipt: the snapshot written at completion, the
 * completed-only party-authorized read, the legacy fallback, and the listing
 * deletion guard that keeps a receipt from being cascaded away.
 */
class ReceiptTest extends TestCase
{
    use RefreshDatabase;

    private User $buyer;

    private User $seller;

    private User $stranger;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();

        Notification::fake();

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

    private function createTransaction(
        Listing $listing,
        ?string $collectionMethod = 'farm_pickup',
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
            'payment_method' => 'gcash',
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

    private function completeTransaction(
        Listing $listing,
        ?string $collectionMethod = 'farm_pickup',
    ): Transaction {
        $transaction = $this->createTransaction($listing, $collectionMethod);

        $this->act($transaction, $this->seller, 'preparing')->assertOk();

        if ($collectionMethod === 'seller_arranged_delivery') {
            $this->act($transaction, $this->seller, 'on-the-way')->assertOk();
            $this->act($transaction, $this->seller, 'delivered')->assertOk();
        } else {
            $this->act($transaction, $this->seller, 'ready-for-pickup')->assertOk();
            $this->act($transaction, $this->seller, 'picked-up')->assertOk();
        }

        $this->act($transaction, $this->buyer, 'complete')->assertOk();

        return $transaction->refresh();
    }

    private function receipt(Transaction $transaction, User $user): TestResponse
    {
        return $this->withHeader(
            'Authorization',
            'Bearer '.$this->mobileToken($user),
        )->getJson('/api/transactions/'.$transaction->id.'/receipt');
    }

    #[Test]
    public function buyer_sees_the_completed_receipt_snapshot(): void
    {
        $listing = $this->createListing();
        $transaction = $this->completeTransaction($listing, 'seller_arranged_delivery');

        $this->assertNotNull($transaction->completed_at);
        $this->assertIsArray($transaction->receipt_snapshot);

        $response = $this->receipt($transaction, $this->buyer);

        $response->assertOk()
            ->assertJsonPath('data.version', 1)
            ->assertJsonPath('data.reference', sprintf('TRX-%03d', $transaction->id))
            ->assertJsonPath('data.buyer.name', 'Pedro Reyes')
            ->assertJsonPath('data.seller.name', 'Juan Dela Cruz')
            ->assertJsonPath('data.listing.livestock_type', 'cattle')
            ->assertJsonPath('data.listing.breed', 'Angus')
            ->assertJsonPath('data.quantity', 1)
            ->assertJsonPath('data.total_amount', '50000.00')
            ->assertJsonPath('data.payment_method', 'gcash')
            ->assertJsonPath('data.collection_method', 'seller_arranged_delivery')
            ->assertJsonPath('data.status', 'completed')
            ->assertJsonMissingPath('data.buyer.email')
            ->assertJsonMissingPath('data.seller.email');

        $this->assertNotNull($response->json('data.completed_at'));
    }

    #[Test]
    public function the_seller_may_read_the_same_receipt(): void
    {
        $listing = $this->createListing();
        $transaction = $this->completeTransaction($listing);

        $this->receipt($transaction, $this->seller)
            ->assertOk()
            ->assertJsonPath('data.buyer.name', 'Pedro Reyes')
            ->assertJsonPath('data.seller.name', 'Juan Dela Cruz');
    }

    #[Test]
    public function a_pending_transaction_has_no_receipt(): void
    {
        $listing = $this->createListing();
        $transaction = $this->createTransaction($listing);

        $this->receipt($transaction, $this->buyer)->assertStatus(409);
    }

    #[Test]
    public function a_cancelled_transaction_has_no_receipt(): void
    {
        $listing = $this->createListing();
        $transaction = $this->createTransaction($listing, 'farm_pickup', [
            'status' => TransactionStatus::Cancelled,
            'fulfillment_status' => null,
        ]);

        $this->receipt($transaction, $this->buyer)->assertStatus(409);
    }

    #[Test]
    public function a_stranger_gets_the_same_not_found_as_a_missing_record(): void
    {
        $listing = $this->createListing();
        $transaction = $this->completeTransaction($listing);

        $this->receipt($transaction, $this->stranger)->assertStatus(404);
    }

    #[Test]
    public function a_guest_cannot_read_a_receipt(): void
    {
        $listing = $this->createListing();
        $transaction = $this->completeTransaction($listing);

        // `withHeader` above persists on the test client; clear it so this is
        // genuinely a guest request.
        $this->flushHeaders();

        $this->getJson('/api/transactions/'.$transaction->id.'/receipt')
            ->assertStatus(401);
    }

    #[Test]
    public function an_admin_token_cannot_use_the_mobile_receipt_route(): void
    {
        $listing = $this->createListing();
        $transaction = $this->completeTransaction($listing);
        $token = $this->admin->createToken('admin', ['admin'])->plainTextToken;

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->getJson('/api/transactions/'.$transaction->id.'/receipt')
            ->assertStatus(403);
    }

    #[Test]
    public function the_snapshot_survives_a_listing_edit(): void
    {
        $listing = $this->createListing();
        $transaction = $this->completeTransaction($listing);

        $this->withHeader(
            'Authorization',
            'Bearer '.$this->mobileToken($this->seller),
        )->patchJson('/api/seller/listings/'.$listing->id, [
            'livestock_type' => 'goat',
            'breed' => 'Boer',
        ])->assertOk();

        $this->receipt($transaction, $this->buyer)
            ->assertOk()
            ->assertJsonPath('data.listing.livestock_type', 'cattle')
            ->assertJsonPath('data.listing.breed', 'Angus');
    }

    #[Test]
    public function a_repeated_completion_does_not_change_the_receipt(): void
    {
        $listing = $this->createListing();
        $transaction = $this->completeTransaction($listing);

        $completedAt = $transaction->completed_at;
        $snapshot = $transaction->receipt_snapshot;

        $this->act($transaction, $this->buyer, 'complete')->assertStatus(409);

        $transaction->refresh();

        $this->assertTrue($completedAt->equalTo($transaction->completed_at));
        $this->assertSame($snapshot, $transaction->receipt_snapshot);
    }

    #[Test]
    public function a_legacy_completed_row_falls_back_to_live_values(): void
    {
        $listing = $this->createListing();
        $transaction = $this->createTransaction($listing, 'farm_pickup', [
            'status' => TransactionStatus::Completed,
            'fulfillment_status' => FulfillmentStatus::Completed,
            'completed_at' => null,
            'receipt_snapshot' => null,
        ]);

        $this->receipt($transaction, $this->buyer)
            ->assertOk()
            ->assertJsonPath('data.reference', sprintf('TRX-%03d', $transaction->id))
            ->assertJsonPath('data.buyer.name', 'Pedro Reyes')
            ->assertJsonPath('data.listing.livestock_type', 'cattle')
            ->assertJsonPath('data.status', 'completed');
    }

    #[Test]
    public function a_listing_with_a_completed_transaction_cannot_be_deleted(): void
    {
        $listing = $this->createListing();
        $this->completeTransaction($listing);

        Listing::query()->whereKey($listing->id)->update([
            'status' => ListingStatus::Inactive->value,
        ]);
        $listing->refresh();

        $this->withHeader(
            'Authorization',
            'Bearer '.$this->mobileToken($this->seller),
        )->deleteJson('/api/seller/listings/'.$listing->id)
            ->assertStatus(409);

        $this->assertDatabaseHas('listings', ['id' => $listing->id]);
    }

    #[Test]
    public function an_inactive_listing_without_completed_transactions_still_deletes(): void
    {
        $listing = $this->createListing([
            'status' => ListingStatus::Inactive,
        ]);

        $this->withHeader(
            'Authorization',
            'Bearer '.$this->mobileToken($this->seller),
        )->deleteJson('/api/seller/listings/'.$listing->id)
            ->assertOk();

        $this->assertDatabaseMissing('listings', ['id' => $listing->id]);
    }
}
