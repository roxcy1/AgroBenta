<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Add the provider's status and structured prediction metadata while
     * keeping existing estimate rows valid. The value/range columns are
     * unchanged; min/max remain nullable and are never fabricated.
     */
    public function up(): void
    {
        Schema::table('ai_price_estimates', function (Blueprint $table) {
            $table->string('status', 20)->default('ok')->after('basis');
            $table->json('provider_metadata')->nullable()->after('status');
        });
    }

    public function down(): void
    {
        Schema::table('ai_price_estimates', function (Blueprint $table) {
            $table->dropColumn(['status', 'provider_metadata']);
        });
    }
};
