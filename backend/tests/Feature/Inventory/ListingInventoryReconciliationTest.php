<?php

namespace Tests\Feature\Inventory;

use App\Enums\ListingStatus;
use App\Enums\TransactionStatus;
use App\Enums\UserRole;
use App\Models\Listing;
use App\Models\ListingInventoryReconciliation;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class ListingInventoryReconciliationTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    private User $seller;

    private User $buyer;

    protected function setUp(): void
    {
        parent::setUp();

        $this->admin = User::factory()->admin()->create();
        $this->seller = User::factory()->seller()->create();
        $this->buyer = User::factory()->create(['role' => UserRole::User]);
    }

    private function token(User $user, string $ability): string
    {
        return $user->createToken($ability, [$ability])->plainTextToken;
    }

    private function legacyListing(): Listing
    {
        return Listing::query()->create([
            'seller_id' => $this->seller->id,
            'livestock_type' => 'goat',
            'breed' => 'Native',
            'quantity' => 5,
            'total_quantity' => null,
            'legacy_quantity_snapshot' => 5,
            'inventory_reconciliation_required' => true,
            'asking_price' => 2000,
            'location' => 'Trinidad, Bohol',
            'short_description' => 'Legacy inventory',
            'photos' => [],
            'status' => ListingStatus::Active,
        ]);
    }

    private function transaction(Listing $listing, string $status, int $quantity): Transaction
    {
        return Transaction::query()->create([
            'buyer_id' => $this->buyer->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'quantity' => $quantity,
            'total_amount' => 2000 * $quantity,
            'status' => $status,
            'inventory_reserved' => false,
            'inventory_accounted' => false,
        ]);
    }

    #[Test]
    public function an_admin_reconciles_verified_inventory_and_accounts_legacy_transactions_once(): void
    {
        $listing = $this->legacyListing();
        $pending = $this->transaction($listing, TransactionStatus::Pending->value, 2);
        $completed = $this->transaction($listing, TransactionStatus::Completed->value, 3);

        $this->withHeader('Authorization', 'Bearer '.$this->token($this->admin, 'admin'))
            ->postJson('/api/admin/listings/'.$listing->id.'/inventory/reconcile', [
                'verified_physical_quantity' => 4,
                'verified_externally_sold_quantity' => 1,
                'accounted_transaction_ids' => [$completed->id, $pending->id],
                'reason' => 'Count confirmed with the seller.',
                'evidence' => 'Signed farm inventory sheet #42.',
            ])
            ->assertOk()
            ->assertJsonPath('data.listing.inventory_reconciliation_required', false)
            ->assertJsonPath('data.listing.total_quantity', 10)
            ->assertJsonPath('data.listing.reserved_quantity', 2)
            ->assertJsonPath('data.listing.sold_quantity', 4)
            ->assertJsonPath('data.listing.available_quantity', 4)
            ->assertJsonPath('data.reconciliation.admin.id', $this->admin->id)
            ->assertJsonPath('data.reconciliation.accounted_transaction_ids.0', $pending->id);

        $this->assertSame(4, (int) $listing->refresh()->quantity);
        $this->assertSame(10, (int) $listing->total_quantity);
        $this->assertSame(1, (int) $listing->externally_sold_quantity);
        $this->assertSame('pending', $pending->refresh()->status->value);
        $this->assertTrue((bool) $pending->inventory_reserved);
        $this->assertTrue((bool) $pending->inventory_accounted);
        $this->assertSame('completed', $completed->refresh()->status->value);
        $this->assertFalse((bool) $completed->inventory_reserved);
        $this->assertTrue((bool) $completed->inventory_accounted);
        $this->assertSame(1, ListingInventoryReconciliation::query()->count());
    }

    #[Test]
    public function an_incomplete_legacy_transaction_allocation_cannot_clear_reconciliation(): void
    {
        $listing = $this->legacyListing();
        $pending = $this->transaction($listing, TransactionStatus::Pending->value, 2);
        $completed = $this->transaction($listing, TransactionStatus::Completed->value, 3);

        $this->withHeader('Authorization', 'Bearer '.$this->token($this->admin, 'admin'))
            ->postJson('/api/admin/listings/'.$listing->id.'/inventory/reconcile', [
                'verified_physical_quantity' => 4,
                'verified_externally_sold_quantity' => 1,
                'accounted_transaction_ids' => [$pending->id],
                'reason' => 'Incomplete transaction allocation.',
                'evidence' => 'Evidence file A.',
            ])
            ->assertStatus(409);

        $this->assertTrue((bool) $listing->refresh()->inventory_reconciliation_required);
        $this->assertSame(5, (int) $listing->quantity);
        $this->assertSame(0, ListingInventoryReconciliation::query()->count());
        $this->assertFalse((bool) $pending->refresh()->inventory_accounted);
        $this->assertFalse((bool) $completed->refresh()->inventory_accounted);
    }

    #[Test]
    public function reconciliation_requires_evidence_for_verified_sales(): void
    {
        $listing = $this->legacyListing();
        $completed = $this->transaction($listing, TransactionStatus::Completed->value, 2);

        $this->withHeader('Authorization', 'Bearer '.$this->token($this->admin, 'admin'))
            ->postJson('/api/admin/listings/'.$listing->id.'/inventory/reconcile', [
                'verified_physical_quantity' => 3,
                'verified_externally_sold_quantity' => 0,
                'accounted_transaction_ids' => [$completed->id],
                'reason' => 'Verified completed sale.',
            ])
            ->assertStatus(422);

        $this->assertTrue((bool) $listing->refresh()->inventory_reconciliation_required);
        $this->assertFalse((bool) $completed->refresh()->inventory_accounted);
    }

    #[Test]
    public function non_admins_cannot_reconcile_inventory(): void
    {
        $listing = $this->legacyListing();

        $this->withHeader('Authorization', 'Bearer '.$this->token($this->buyer, 'mobile'))
            ->postJson('/api/admin/listings/'.$listing->id.'/inventory/reconcile', [])
            ->assertForbidden();

        $this->assertTrue((bool) $listing->refresh()->inventory_reconciliation_required);
    }
}
