<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Snapshot the applicant's required contact details on each verification.
     * Nullable columns preserve records submitted before these fields were added;
     * the mobile submission request requires both for every new record.
     */
    public function up(): void
    {
        Schema::table('seller_verifications', function (Blueprint $table): void {
            $table->string('phone', 32)->nullable()->after('user_id');
            $table->string('address', 191)->nullable()->after('phone');
        });
    }

    public function down(): void
    {
        Schema::table('seller_verifications', function (Blueprint $table): void {
            $table->dropColumn(['phone', 'address']);
        });
    }
};
