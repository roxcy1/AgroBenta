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
            $table->enum('collection_date_option', [
                'specific_date',
                'next_few_days',
                'this_week',
            ])->nullable()->after('preferred_schedule');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('inquiries', function (Blueprint $table): void {
            $table->dropColumn('collection_date_option');
        });
    }
};
