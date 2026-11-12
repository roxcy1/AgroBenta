<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Add the fulfillment progression without changing `transactions.status`.
 *
 * New transactions start at `confirmed`. Existing pending records are treated
 * as confirmed so they can follow the same seller/buyer flow; completed records
 * are backfilled as completed. Cancelled records keep a null fulfillment stage
 * because their progression stopped without a handover, and the transaction
 * status already carries the terminal outcome.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('transactions', function (Blueprint $table): void {
            $table->string('fulfillment_status', 32)
                ->nullable()
                ->after('status');
        });

        DB::table('transactions')
            ->where('status', 'pending')
            ->update(['fulfillment_status' => 'confirmed']);

        DB::table('transactions')
            ->where('status', 'completed')
            ->update(['fulfillment_status' => 'completed']);
    }

    public function down(): void
    {
        Schema::table('transactions', function (Blueprint $table): void {
            $table->dropColumn('fulfillment_status');
        });
    }
};
