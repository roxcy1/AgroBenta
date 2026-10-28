<?php

namespace Tests\Feature\Transaction;

use App\Enums\ListingStatus;
use App\Enums\TransactionStatus;
use App\Enums\UserRole;
use App\Models\Listing;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Mobile transactions — contract §5.6 minus `complete`.
 *
 * A buyer may create a pending transaction against an active listing they do
 * not own; either party may cancel a pending one; terminal states are
 * immutable; and `complete` answers 501 because OQ-15 leaves the confirming
 * actor undecided.
 */
class MobileTransactionTest extends TestCase
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
            'email' => 'juan@agrobenta.test',
        ]);

        $this->stranger = User::factory()->create([
            'role' => UserRole::User,
            'name' => 'Ramon Cruz',
        ]);
    }

    private function mobileToken(User $user): string
    {
        return $user->createToken('mobile', ['mobile'])->plainTextToken;
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
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

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function createTransaction(Listing $listing, User $buyer, array $overrides = []): Transaction
    {
        return Transaction::create(array_merge([
            'buyer_id' => $buyer->id,
            'seller_id' => $listing->seller_id,
            'listing_id' => $listing->id,
            'quantity' => 1,
            'total_amount' => 50000.00,
            'status' => TransactionStatus::Pending,
        ], $overrides));
    }

    /**
     * @param  array<string, mixed>  $query
     */
    private function list(array $query = [], ?User $user = null): TestResponse
    {
        return $this->withHeader(
            'Authorization',
            'Bearer '.$this->mobileToken($user ?? $this->buyer),
        )->getJson('/api/transactions'.($query === [] ? '' : '?'.http_build_query($query)));
    }

    #[Test]
    public function a_guest_cannot_reach_transactions(): void
    {
        $this->getJson('/api/transactions')->assertStatus(401);
        $this->postJson('/api/transactions', [])->assertStatus(401);
    }

    #[Test]
    public function a_user_sees_only_their_own_transactions(): void
    {
        $listing = $this->createListing($this->seller);
        $mine = $this->createTransaction($listing, $this->buyer);
        $theirs = $this->createTransaction($listing, $this->stranger);

        $ids = $this->list()->assertOk()->json('data.transactions.*.id');

        $this->assertContains($mine->id, $ids);
        $this->assertNotContains($theirs->id, $ids);
    }

    #[Test]
    public function role_narrows_to_one_side_of_the_caller_records(): void
    {
        $listing = $this->createListing($this->seller);
        $asBuyer = $this->createTransaction($listing, $this->buyer);

        $asSeller = Transaction::create([
            'buyer_id' => $this->stranger->id,
            'seller_id' => $this->buyer->id,
            'listing_id' => $listing->id,
            'quantity' => 1,
            'total_amount' => 10000.00,
            'status' => TransactionStatus::Pending,
        ]);

        $buyerIds = $this->list(['role' => 'buyer'])->assertOk()->json('data.transactions.*.id');
        $this->assertContains($asBuyer->id, $buyerIds);
        $this->assertNotContains($asSeller->id, $buyerIds);

        $sellerIds = $this->list(['role' => 'seller'])->assertOk()->json('data.transactions.*.id');
        $this->assertContains($asSeller->id, $sellerIds);
        $this->assertNotContains($asBuyer->id, $sellerIds);
    }

    #[Test]
    public function a_seller_sales_list_excludes_their_purchases_and_foreign_sales(): void
    {
        $ownListing = $this->createListing($this->seller);
        $sale = $this->createTransaction($ownListing, $this->buyer);

        $otherListing = $this->createListing($this->stranger);
        $purchase = $this->createTransaction($otherListing, $this->seller);
        $foreignSale = $this->createTransaction($otherListing, $this->buyer);

        $transactions = $this->list(['role' => 'seller'], $this->seller)
            ->assertOk()
            ->json('data.transactions');
        $ids = array_column($transactions, 'id');

        $this->assertSame([$sale->id], $ids);
        $this->assertNotContains($purchase->id, $ids);
        $this->assertNotContains($foreignSale->id, $ids);
        $this->assertSame('seller', $transactions[0]['role']);
        $this->assertSame(
            $this->buyer->id,
            $transactions[0]['counterparty']['id'],
        );
    }

    #[Test]
    public function ownership_filters_are_refused(): void
    {
        $this->list(['buyer_id' => $this->buyer->id])->assertStatus(422);
        $this->list(['seller_id' => $this->seller->id])->assertStatus(422);
    }

    #[Test]
    public function status_narrows_to_one_lifecycle_state(): void
    {
        $listing = $this->createListing($this->seller);
        $pending = $this->createTransaction($listing, $this->buyer);
        $cancelled = $this->createTransaction($listing, $this->buyer, [
            'quantity' => 2,
            'status' => TransactionStatus::Cancelled,
        ]);

        $ids = $this->list(['status' => 'pending'])->assertOk()->json('data.transactions.*.id');
        $this->assertContains($pending->id, $ids);
        $this->assertNotContains($cancelled->id, $ids);
    }

    #[Test]
    public function a_stranger_cannot_read_a_transaction(): void
    {
        $listing = $this->createListing($this->seller);
        $transaction = $this->createTransaction($listing, $this->buyer);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->stranger))
            ->getJson('/api/transactions/'.$transaction->id)
            ->assertStatus(404);
    }

    #[Test]
    public function detail_exposes_only_the_counterparty_contact(): void
    {
        $listing = $this->createListing($this->seller);
        $transaction = $this->createTransaction($listing, $this->buyer);

        $buyerView = $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->buyer))
            ->getJson('/api/transactions/'.$transaction->id)
            ->assertOk()
            ->json('data');

        $this->assertSame('buyer', $buyerView['role']);
        $this->assertSame($this->seller->id, $buyerView['counterparty']['id']);
        $this->assertSame($this->seller->email, $buyerView['counterparty']['email']);
        $this->assertArrayNotHasKey('buyer', $buyerView);
        $this->assertArrayNotHasKey('seller', $buyerView);

        // Sanctum's RequestGuard caches the first user it resolves for the
        // whole PHP process and does not clear that cache when the request
        // changes (laravel/framework#56809). Within one test the app instance
        // is shared, so without forgetting the guards the seller's request
        // below would silently resolve as the buyer.
        $this->app->make('auth')->forgetGuards();

        $sellerView = $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->getJson('/api/transactions/'.$transaction->id)
            ->assertOk()
            ->json('data');

        $this->assertSame('seller', $sellerView['role']);
        $this->assertSame($this->buyer->id, $sellerView['counterparty']['id']);
    }

    #[Test]
    public function a_buyer_can_create_a_pending_transaction(): void
    {
        $listing = $this->createListing($this->seller);

        $data = $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->buyer))
            ->postJson('/api/transactions', [
                'listing_id' => $listing->id,
                'quantity' => 2,
            ])
            ->assertStatus(201)
            ->json('data');

        $this->assertSame('pending', $data['status']);
        // Server-derived: 50000.00 x 2, never what the client sent.
        $this->assertSame('100000.00', $data['total_amount']);
        $this->assertSame(2, $data['quantity']);
        $this->assertSame('buyer', $data['role']);
    }

    #[Test]
    public function server_owned_create_fields_are_rejected(): void
    {
        $listing = $this->createListing($this->seller);

        foreach (['buyer_id', 'seller_id', 'total_amount', 'status'] as $field) {
            $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->buyer))
                ->postJson('/api/transactions', [
                    'listing_id' => $listing->id,
                    'quantity' => 1,
                    $field => 'x',
                ])
                ->assertStatus(422);
        }
    }

    #[Test]
    public function a_seller_cannot_transact_on_their_own_listing(): void
    {
        $listing = $this->createListing($this->seller);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/transactions', [
                'listing_id' => $listing->id,
                'quantity' => 1,
            ])
            ->assertStatus(409);
    }

    #[Test]
    public function a_non_active_listing_cannot_be_transacted(): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Pending]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->buyer))
            ->postJson('/api/transactions', [
                'listing_id' => $listing->id,
                'quantity' => 1,
            ])
            ->assertStatus(409);
    }

    #[Test]
    public function a_sold_listing_cannot_be_transacted(): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Sold]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->buyer))
            ->postJson('/api/transactions', [
                'listing_id' => $listing->id,
                'quantity' => 1,
            ])
            ->assertStatus(409);

        // No transaction was persisted for the sold listing.
        $this->assertDatabaseMissing('transactions', [
            'listing_id' => $listing->id,
            'buyer_id' => $this->buyer->id,
        ]);
    }

    #[Test]
    public function an_active_listing_can_be_transacted_control(): void
    {
        $listing = $this->createListing($this->seller);

        $data = $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->buyer))
            ->postJson('/api/transactions', [
                'listing_id' => $listing->id,
                'quantity' => 1,
            ])
            ->assertStatus(201)
            ->json('data');

        $this->assertSame('pending', $data['status']);

        // The transaction was persisted.
        $this->assertDatabaseHas('transactions', [
            'id' => $data['id'],
            'listing_id' => $listing->id,
            'buyer_id' => $this->buyer->id,
            'status' => TransactionStatus::Pending->value,
        ]);
    }

    #[Test]
    public function insufficient_stock_is_refused(): void
    {
        $listing = $this->createListing($this->seller, ['quantity' => 1]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->buyer))
            ->postJson('/api/transactions', [
                'listing_id' => $listing->id,
                'quantity' => 2,
            ])
            ->assertStatus(409);
    }

    #[Test]
    public function the_buyer_can_cancel_a_pending_transaction(): void
    {
        $listing = $this->createListing($this->seller);
        $transaction = $this->createTransaction($listing, $this->buyer);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->buyer))
            ->postJson('/api/transactions/'.$transaction->id.'/cancel')
            ->assertOk()
            ->assertJsonPath('data.status', 'cancelled');
    }

    #[Test]
    public function the_seller_can_cancel_a_pending_transaction(): void
    {
        $listing = $this->createListing($this->seller);
        $transaction = $this->createTransaction($listing, $this->buyer);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/transactions/'.$transaction->id.'/cancel')
            ->assertOk()
            ->assertJsonPath('data.status', 'cancelled');
    }

    #[Test]
    public function a_terminal_transaction_cannot_be_cancelled(): void
    {
        $listing = $this->createListing($this->seller);
        $transaction = $this->createTransaction($listing, $this->buyer, [
            'status' => TransactionStatus::Cancelled,
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->buyer))
            ->postJson('/api/transactions/'.$transaction->id.'/cancel')
            ->assertStatus(409);
    }

    #[Test]
    public function completion_is_explicitly_unavailable(): void
    {
        $listing = $this->createListing($this->seller);
        $transaction = $this->createTransaction($listing, $this->buyer);

        // OQ-15: the confirming actor is undecided, so the transition stays
        // unimplemented. An explicit 501 says so; the client never calls it.
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->buyer))
            ->postJson('/api/transactions/'.$transaction->id.'/complete')
            ->assertStatus(501);

        $this->assertSame('pending', $transaction->refresh()->status->value);
    }
}
