<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('inquiries', function (Blueprint $table): void {
            $table->enum('payment_method', ['cash', 'gcash', 'maya', 'other'])->nullable()
                ->after('preferred_schedule');
            $table->enum('collection_method', [
                'farm_pickup',
                'buyer_arranged_transportation',
                'discuss_with_seller',
            ])->nullable()->after('payment_method');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('inquiries', function (Blueprint $table): void {
            $table->dropColumn(['payment_method', 'collection_method']);
        });
    }
};
