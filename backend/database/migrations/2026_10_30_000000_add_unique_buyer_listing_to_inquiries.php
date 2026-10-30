<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * One inquiry per buyer per listing, whatever its status.
     *
     * The service checks first and returns a 409; this index is what makes the
     * rule true under two concurrent requests, where both lookups can miss.
     *
     * `listing_id` is nullable (`nullOnDelete`), and SQL treats NULLs as
     * distinct, so an inquiry whose listing was deleted does not block a new
     * inquiry about a different listing.
     */
    public function up(): void
    {
        Schema::table('inquiries', function (Blueprint $table): void {
            $table->unique(
                ['buyer_id', 'listing_id'],
                'inquiries_buyer_id_listing_id_unique',
            );
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('inquiries', function (Blueprint $table): void {
            $table->dropUnique('inquiries_buyer_id_listing_id_unique');
        });
    }
};
