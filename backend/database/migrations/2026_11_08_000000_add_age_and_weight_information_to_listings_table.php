<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Add the seller's age/weight information type.
     *
     * Both columns are nullable so existing rows remain valid and are not
     * rewritten. New listings are required to supply them by the request
     * validation; legacy rows may be edited without a forced backfill and are
     * required to supply them before submission.
     */
    public function up(): void
    {
        Schema::table('listings', function (Blueprint $table) {
            $table->string('age_information', 20)->nullable()->after('age_unit');
            $table->string('weight_information', 20)->nullable()->after('weight_unit');
        });
    }

    /**
     * Reverse the migration.
     */
    public function down(): void
    {
        Schema::table('listings', function (Blueprint $table) {
            $table->dropColumn(['age_information', 'weight_information']);
        });
    }
};
