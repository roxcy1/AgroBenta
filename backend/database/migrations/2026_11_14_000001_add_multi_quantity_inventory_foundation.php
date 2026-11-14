<?php

use App\Services\Inventory\LegacyInventoryBackfillPolicy;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('listings', function (Blueprint $table): void {
            // `quantity` remains the available-stock column used by existing
            // clients. A nullable total is intentional for legacy rows whose
            // transaction history cannot prove their inventory.
            $table->unsignedInteger('total_quantity')->nullable()->after('quantity');
            $table->unsignedInteger('externally_sold_quantity')
                ->default(0)
                ->after('total_quantity');
            $table->boolean('inventory_reconciliation_required')
                ->default(false)
                ->after('externally_sold_quantity');
            $table->unsignedInteger('legacy_quantity_snapshot')
                ->nullable()
                ->after('inventory_reconciliation_required');
        });

        Schema::table('transactions', function (Blueprint $table): void {
            // `inventory_reserved` means a reservation/release occurred. This
            // separate bit says the transaction is represented in the new
            // inventory accounting. Legacy rows default false and are never
            // silently treated as reservations or sales.
            $table->boolean('inventory_accounted')
                ->default(false)
                ->after('inventory_reserved');
            $table->timestamp('inventory_accounted_at')->nullable()->after('inventory_accounted');
            $table->foreignId('inventory_accounted_by')
                ->nullable()
                ->after('inventory_accounted_at')
                ->constrained('users')
                ->nullOnDelete();
        });

        Schema::create('listing_inventory_reconciliations', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('listing_id')->constrained()->cascadeOnDelete();
            $table->foreignId('admin_id')->constrained('users');
            $table->unsignedInteger('verified_physical_quantity');
            $table->unsignedInteger('verified_pending_quantity');
            $table->unsignedInteger('verified_completed_quantity');
            $table->unsignedInteger('verified_externally_sold_quantity');
            $table->unsignedInteger('verified_total_quantity');
            $table->unsignedInteger('verified_available_quantity');
            $table->json('accounted_transaction_ids');
            $table->string('reason', 1000);
            $table->text('evidence')->nullable();
            $table->timestamps();

            $table->index(['listing_id', 'created_at']);
            $table->index(['admin_id', 'created_at']);
        });

        $this->backfillProvableInventory();
    }

    /**
     * Backfill only rows whose current available quantity and transaction
     * history can be reconciled without inventing prior reservations or sales.
     *
     * Existing reservations (`inventory_reserved = true`) prove stock was
     * removed from `listings.quantity`; their quantity is therefore added back
     * to the stored total. A legacy pending/completed transaction with the flag
     * false does not prove an inventory adjustment. Such a listing, including
     * its quantity and transactions, is retained unchanged and marked for
     * administrator reconciliation.
     *
     * Historical seller-marked-sold rows are always quarantined: the old action
     * changed status only, so the number sold externally cannot be recovered.
     */
    private function backfillProvableInventory(): void
    {
        DB::table('listings')
            ->orderBy('id')
            ->chunkById(200, function ($listings): void {
                foreach ($listings as $listing) {
                    $transactions = DB::table('transactions')
                        ->where('listing_id', $listing->id)
                        ->get(['id', 'status', 'quantity', 'inventory_reserved']);

                    // A true reservation flag is proof that stock was already
                    // removed. Preserve that accounting even when another
                    // transaction makes the listing itself ambiguous.
                    DB::table('transactions')
                        ->where('listing_id', $listing->id)
                        ->where('inventory_reserved', true)
                        ->whereIn('status', ['pending', 'completed'])
                        ->update([
                            'inventory_accounted' => true,
                            'inventory_accounted_at' => null,
                            'inventory_accounted_by' => null,
                        ]);

                    $decision = app(LegacyInventoryBackfillPolicy::class)->assess(
                        (int) $listing->quantity,
                        (string) $listing->status,
                        $transactions,
                    );

                    DB::table('listings')
                        ->where('id', $listing->id)
                        ->update([
                            'total_quantity' => $decision['total_quantity'],
                            'inventory_reconciliation_required' => $decision['reconciliation_required'],
                            'legacy_quantity_snapshot' => $decision['legacy_quantity_snapshot'],
                        ]);

                }
            });
    }

    public function down(): void
    {
        Schema::dropIfExists('listing_inventory_reconciliations');

        Schema::table('transactions', function (Blueprint $table): void {
            $table->dropForeign(['inventory_accounted_by']);
            $table->dropColumn('inventory_accounted');
            $table->dropColumn('inventory_accounted_at');
            $table->dropColumn('inventory_accounted_by');
        });

        Schema::table('listings', function (Blueprint $table): void {
            $table->dropColumn([
                'total_quantity',
                'externally_sold_quantity',
                'inventory_reconciliation_required',
                'legacy_quantity_snapshot',
            ]);
        });
    }
};
