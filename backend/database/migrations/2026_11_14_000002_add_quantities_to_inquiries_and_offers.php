<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('inquiries', function (Blueprint $table): void {
            // Legacy inquiries represent a request for one head. The default
            // preserves their meaning without inventing a quantity.
            $table->unsignedInteger('requested_quantity')
                ->default(1)
                ->after('listing_id');
        });

        Schema::table('offers', function (Blueprint $table): void {
            // A legacy offer covered the single head it reserved. `proposed_amount`
            // remains the total agreed amount for the offer's quantity.
            $table->unsignedInteger('proposed_quantity')
                ->default(1)
                ->after('proposed_amount');
        });
    }

    public function down(): void
    {
        Schema::table('offers', function (Blueprint $table): void {
            $table->dropColumn('proposed_quantity');
        });

        Schema::table('inquiries', function (Blueprint $table): void {
            $table->dropColumn('requested_quantity');
        });
    }
};
