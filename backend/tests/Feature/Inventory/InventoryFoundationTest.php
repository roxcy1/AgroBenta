<?php

namespace Tests\Feature\Inventory;

use App\Enums\ListingStatus;
use App\Models\Listing;
use App\Models\ListingInventoryReconciliation;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class InventoryFoundationTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function a_new_legacy_shaped_listing_initializes_total_from_available_quantity(): void
    {
        $seller = User::factory()->seller()->create();

        $listing = Listing::query()->create([
            'seller_id' => $seller->id,
            'livestock_type' => 'goat',
            'breed' => 'Native',
            'quantity' => 5,
            'asking_price' => 1000,
            'location' => 'Trinidad, Bohol',
            'short_description' => 'Five goats',
            'photos' => [],
            'status' => ListingStatus::Draft,
        ]);

        $this->assertSame(5, $listing->refresh()->quantity);
        $this->assertSame(5, $listing->total_quantity);
        $this->assertSame(0, $listing->externally_sold_quantity);
        $this->assertFalse($listing->inventory_reconciliation_required);
    }

    #[Test]
    public function an_unreconciled_listing_does_not_have_a_guessed_total(): void
    {
        $seller = User::factory()->seller()->create();

        $listing = Listing::query()->create([
            'seller_id' => $seller->id,
            'livestock_type' => 'goat',
            'breed' => 'Native',
            'quantity' => 3,
            'total_quantity' => null,
            'inventory_reconciliation_required' => true,
            'legacy_quantity_snapshot' => 3,
            'asking_price' => 1000,
            'location' => 'Trinidad, Bohol',
            'short_description' => 'Legacy listing',
            'photos' => [],
            'status' => ListingStatus::Active,
        ]);

        $this->assertNull($listing->refresh()->total_quantity);
        $this->assertSame(3, $listing->quantity);
        $this->assertSame(3, $listing->legacy_quantity_snapshot);
        $this->assertTrue($listing->inventory_reconciliation_required);
    }

    #[Test]
    public function an_inventory_reconciliation_preserves_auditor_evidence_and_transaction_ids(): void
    {
        $seller = User::factory()->seller()->create();
        $admin = User::factory()->admin()->create();
        $listing = Listing::query()->create([
            'seller_id' => $seller->id,
            'livestock_type' => 'goat',
            'breed' => 'Native',
            'quantity' => 0,
            'total_quantity' => null,
            'inventory_reconciliation_required' => true,
            'legacy_quantity_snapshot' => 5,
            'asking_price' => 1000,
            'location' => 'Trinidad, Bohol',
            'short_description' => 'Legacy listing',
            'photos' => [],
            'status' => ListingStatus::Active,
        ]);
        $transaction = Transaction::query()->create([
            'buyer_id' => User::factory()->create()->id,
            'seller_id' => $seller->id,
            'listing_id' => $listing->id,
            'quantity' => 2,
            'total_amount' => 2000,
            'status' => 'pending',
            'inventory_reserved' => true,
            'inventory_accounted' => true,
        ]);

        $record = ListingInventoryReconciliation::query()->create([
            'listing_id' => $listing->id,
            'admin_id' => $admin->id,
            'verified_physical_quantity' => 3,
            'verified_pending_quantity' => 2,
            'verified_completed_quantity' => 0,
            'verified_externally_sold_quantity' => 0,
            'verified_total_quantity' => 5,
            'verified_available_quantity' => 3,
            'accounted_transaction_ids' => [$transaction->id],
            'reason' => 'Physical count completed with seller.',
            'evidence' => 'Signed inventory checklist.',
        ]);

        $record->refresh();
        $this->assertSame([$transaction->id], $record->accounted_transaction_ids);
        $this->assertSame($admin->id, $record->admin_id);
        $this->assertSame('Signed inventory checklist.', $record->evidence);
    }
}
