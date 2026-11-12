<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Record whether a transaction actually took stock out of its listing.
 *
 * Transactions created before reservation existed did not decrement
 * `listings.quantity`. The flag starts false and is set true only by a new
 * reservation, so cancelling a historical pending record cannot inflate the
 * seller's available stock.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('transactions', function (Blueprint $table): void {
            $table->boolean('inventory_reserved')
                ->default(false)
                ->after('collection_method');
        });
    }

    public function down(): void
    {
        Schema::table('transactions', function (Blueprint $table): void {
            $table->dropColumn('inventory_reserved');
        });
    }
};
