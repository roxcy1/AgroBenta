<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Add the approved collection choices without dropping the historical
 * `discuss_with_seller` value.
 *
 * MySQL stores this column as an enum, so the new values require a column
 * change. `discuss_with_seller` stays in the list only to preserve existing
 * rows; the mobile form no longer offers it.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('inquiries', function (Blueprint $table): void {
            $table->enum('collection_method', [
                'farm_pickup',
                'buyer_arranged_transportation',
                'seller_arranged_delivery',
                'not_sure_yet',
                'discuss_with_seller',
            ])->nullable()->change();
        });
    }

    public function down(): void
    {
        Schema::table('inquiries', function (Blueprint $table): void {
            $table->enum('collection_method', [
                'farm_pickup',
                'buyer_arranged_transportation',
                'discuss_with_seller',
            ])->nullable()->change();
        });
    }
};
