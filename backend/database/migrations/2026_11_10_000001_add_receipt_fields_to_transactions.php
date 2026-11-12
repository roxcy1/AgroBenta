<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Record when a sale completed and freeze the receipt values as they stood at
 * that moment.
 *
 * `completed_at` is separate from `updated_at` because the latter is an
 * implementation detail: any future write to the row would move it. The receipt
 * snapshot keeps the buyer/seller names and listing identity from drifting when
 * a seller edits a still-active listing after the sale, and gives legacy rows a
 * null snapshot that the resource can fall back from without a backfill.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('transactions', function (Blueprint $table): void {
            $table->timestamp('completed_at')->nullable()->after('fulfillment_status');
            $table->json('receipt_snapshot')->nullable()->after('completed_at');
        });
    }

    public function down(): void
    {
        Schema::table('transactions', function (Blueprint $table): void {
            $table->dropColumn(['completed_at', 'receipt_snapshot']);
        });
    }
};
