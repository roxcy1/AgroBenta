<?php

namespace Tests\Feature\Inventory;

use App\Enums\ListingStatus;
use App\Enums\UserRole;
use App\Models\User;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Exercise the real inventory migrations against pre-feature listing and
 * transaction rows. The app test connection is SQLite :memory: (guarded in
 * TestCase); no persistent application or MySQL database is touched.
 */
class InventoryFoundationMigrationTest extends TestCase
{
    use RefreshDatabase;

    private function inventoryMigration(): Migration
    {
        return require database_path(
            'migrations/2026_11_14_000001_add_multi_quantity_inventory_foundation.php',
        );
    }

    private function quantityMigration(): Migration
    {
        return require database_path(
            'migrations/2026_11_14_000002_add_quantities_to_inquiries_and_offers.php',
        );
    }

    private function insertLegacyListing(User $seller, string $status, int $available): int
    {
        return DB::table('listings')->insertGetId([
            'seller_id' => $seller->id,
            'livestock_type' => 'goat',
            'breed' => 'Native',
            'quantity' => $available,
            'asking_price' => '2500.00',
            'location' => 'Purok 3, Barangay Poblacion, Trinidad, Bohol',
            'short_description' => 'Legacy goats',
            'photos' => json_encode([]),
            'status' => $status,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    private function insertLegacyTransaction(
        int $listingId,
        User $seller,
        User $buyer,
        string $status,
        int $quantity,
        bool $reserved,
    ): int {
        return DB::table('transactions')->insertGetId([
            'buyer_id' => $buyer->id,
            'seller_id' => $seller->id,
            'listing_id' => $listingId,
            'quantity' => $quantity,
            'total_amount' => 2500 * $quantity,
            'status' => $status,
            'inventory_reserved' => $reserved,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    #[Test]
    public function the_migrations_preserve_legacy_rows_and_only_backfill_provable_inventory(): void
    {
        // Return this in-memory test schema to the pre-DEC-10 shape before
        // inserting legacy rows, then execute the exact production migrations.
        $this->quantityMigration()->down();
        $this->inventoryMigration()->down();

        $seller = User::factory()->seller()->create(['role' => UserRole::User]);
        $buyer = User::factory()->create(['role' => UserRole::User]);

        $ambiguous = $this->insertLegacyListing($seller, ListingStatus::Active->value, 5);
        $ambiguousPending = $this->insertLegacyTransaction(
            $ambiguous,
            $seller,
            $buyer,
            'pending',
            2,
            false,
        );
        $ambiguousCompleted = $this->insertLegacyTransaction(
            $ambiguous,
            $seller,
            $buyer,
            'completed',
            3,
            false,
        );

        $provable = $this->insertLegacyListing($seller, ListingStatus::Active->value, 3);
        $provablePending = $this->insertLegacyTransaction(
            $provable,
            $seller,
            $buyer,
            'pending',
            2,
            true,
        );
        $provableCompleted = $this->insertLegacyTransaction(
            $provable,
            $seller,
            $buyer,
            'completed',
            1,
            true,
        );
        $cancelledUnreserved = $this->insertLegacyTransaction(
            $provable,
            $seller,
            $buyer,
            'cancelled',
            4,
            false,
        );

        $historicallySold = $this->insertLegacyListing($seller, ListingStatus::Sold->value, 5);
        $invalidCancelledReservation = $this->insertLegacyListing($seller, ListingStatus::Active->value, 5);
        $cancelledReserved = $this->insertLegacyTransaction(
            $invalidCancelledReservation,
            $seller,
            $buyer,
            'cancelled',
            2,
            true,
        );

        $legacyInquiryId = DB::table('inquiries')->insertGetId([
            'buyer_id' => $buyer->id,
            'seller_id' => $seller->id,
            'listing_id' => $ambiguous,
            'message' => 'Legacy inquiry',
            'status' => 'open',
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        $legacyOfferId = DB::table('offers')->insertGetId([
            'inquiry_id' => $legacyInquiryId,
            'listing_id' => $ambiguous,
            'seller_id' => $seller->id,
            'buyer_id' => $buyer->id,
            'proposed_amount' => '2500.00',
            'status' => 'pending',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $this->inventoryMigration()->up();
        $this->quantityMigration()->up();

        $ambiguousAfter = DB::table('listings')->find($ambiguous);
        $this->assertSame(5, (int) $ambiguousAfter->quantity);
        $this->assertNull($ambiguousAfter->total_quantity);
        $this->assertTrue((bool) $ambiguousAfter->inventory_reconciliation_required);
        $this->assertSame(5, (int) $ambiguousAfter->legacy_quantity_snapshot);
        $this->assertFalse((bool) DB::table('transactions')->find($ambiguousPending)->inventory_accounted);
        $this->assertFalse((bool) DB::table('transactions')->find($ambiguousCompleted)->inventory_accounted);

        $provableAfter = DB::table('listings')->find($provable);
        $this->assertSame(3, (int) $provableAfter->quantity);
        $this->assertSame(6, (int) $provableAfter->total_quantity);
        $this->assertFalse((bool) $provableAfter->inventory_reconciliation_required);
        $this->assertNull($provableAfter->legacy_quantity_snapshot);
        $this->assertTrue((bool) DB::table('transactions')->find($provablePending)->inventory_accounted);
        $this->assertTrue((bool) DB::table('transactions')->find($provableCompleted)->inventory_accounted);
        $this->assertFalse((bool) DB::table('transactions')->find($cancelledUnreserved)->inventory_accounted);

        $soldAfter = DB::table('listings')->find($historicallySold);
        $this->assertTrue((bool) $soldAfter->inventory_reconciliation_required);
        $this->assertNull($soldAfter->total_quantity);
        $this->assertSame(5, (int) $soldAfter->legacy_quantity_snapshot);

        $cancelledAfter = DB::table('listings')->find($invalidCancelledReservation);
        $this->assertTrue((bool) $cancelledAfter->inventory_reconciliation_required);
        $this->assertFalse((bool) DB::table('transactions')->find($cancelledReserved)->inventory_accounted);

        $this->assertSame(6, DB::table('transactions')->count());
        $this->assertSame('pending', DB::table('transactions')->find($ambiguousPending)->status);
        $this->assertSame('completed', DB::table('transactions')->find($ambiguousCompleted)->status);
        $this->assertSame(1, (int) DB::table('inquiries')->where('listing_id', $ambiguous)->value('requested_quantity'));
        $this->assertSame(1, (int) DB::table('offers')->find($legacyOfferId)->proposed_quantity);
    }
}
