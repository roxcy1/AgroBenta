<?php

namespace Tests\Unit;

use App\Services\Inventory\LegacyInventoryBackfillPolicy;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class LegacyInventoryBackfillPolicyTest extends TestCase
{
    #[Test]
    public function an_unreserved_legacy_pending_or_completed_transaction_is_not_backfilled_as_inventory(): void
    {
        $decision = (new LegacyInventoryBackfillPolicy)->assess(
            12,
            'active',
            [
                (object) ['status' => 'pending', 'quantity' => 2, 'inventory_reserved' => false],
                (object) ['status' => 'completed', 'quantity' => 3, 'inventory_reserved' => false],
            ],
        );

        $this->assertTrue($decision['reconciliation_required']);
        $this->assertNull($decision['total_quantity']);
        $this->assertSame(12, $decision['legacy_quantity_snapshot']);
    }

    #[Test]
    public function a_proven_reservation_is_added_to_the_total_without_changing_available_stock(): void
    {
        $decision = (new LegacyInventoryBackfillPolicy)->assess(
            3,
            'active',
            [
                (object) ['status' => 'pending', 'quantity' => 2, 'inventory_reserved' => true],
                (object) ['status' => 'completed', 'quantity' => 1, 'inventory_reserved' => true],
                (object) ['status' => 'cancelled', 'quantity' => 4, 'inventory_reserved' => false],
            ],
        );

        $this->assertFalse($decision['reconciliation_required']);
        $this->assertSame(6, $decision['total_quantity']);
        $this->assertNull($decision['legacy_quantity_snapshot']);
    }

    #[Test]
    public function a_historically_sold_listing_is_never_given_an_invented_external_sale_count(): void
    {
        $decision = (new LegacyInventoryBackfillPolicy)->assess(5, 'sold', []);

        $this->assertTrue($decision['reconciliation_required']);
        $this->assertNull($decision['total_quantity']);
        $this->assertSame(5, $decision['legacy_quantity_snapshot']);
    }

    #[Test]
    public function an_unreserved_legacy_cancellation_neither_inflates_stock_nor_requires_reconciliation(): void
    {
        $decision = (new LegacyInventoryBackfillPolicy)->assess(
            5,
            'active',
            [(object) ['status' => 'cancelled', 'quantity' => 2, 'inventory_reserved' => false]],
        );

        $this->assertFalse($decision['reconciliation_required']);
        $this->assertSame(5, $decision['total_quantity']);
    }

    #[Test]
    public function an_impossible_legacy_cancelled_reservation_requires_reconciliation(): void
    {
        $decision = (new LegacyInventoryBackfillPolicy)->assess(
            5,
            'active',
            [(object) ['status' => 'cancelled', 'quantity' => 2, 'inventory_reserved' => true]],
        );

        $this->assertTrue($decision['reconciliation_required']);
        $this->assertNull($decision['total_quantity']);
    }
}
