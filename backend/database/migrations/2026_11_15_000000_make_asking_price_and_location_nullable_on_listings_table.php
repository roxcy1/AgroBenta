<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * A draft may be incomplete.
 *
 * Price and location are publication requirements, not draft requirements: a
 * seller can ask for an AI reference price before deciding either. Submission
 * re-validates the stored row, so neither field can reach review as NULL.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('listings', function (Blueprint $table) {
            $table->decimal('asking_price', 14, 2)->nullable()->change();
            $table->string('location')->nullable()->change();
        });
    }

    /**
     * Reverting requires a value for every row again. Existing incomplete
     * drafts are backfilled with the least destructive values available: a
     * zero price and an empty location. Neither is publishable, and submission
     * still rejects them.
     */
    public function down(): void
    {
        DB::table('listings')
            ->whereNull('asking_price')
            ->update(['asking_price' => 0]);

        DB::table('listings')
            ->whereNull('location')
            ->update(['location' => '']);

        Schema::table('listings', function (Blueprint $table) {
            $table->decimal('asking_price', 14, 2)->nullable(false)->change();
            $table->string('location')->nullable(false)->change();
        });
    }
};
