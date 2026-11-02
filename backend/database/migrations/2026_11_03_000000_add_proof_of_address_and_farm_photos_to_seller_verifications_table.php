<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     *
     * Adds the remaining manuscript Figure 19 documents, as disk-relative paths
     * on the same private disk as the ID. Both columns are nullable: older
     * records never had these files, and farm photos are optional.
     *
     * `business_name` becomes nullable because the farm/business name is
     * optional (functional documentation §3.3).
     */
    public function up(): void
    {
        Schema::table('seller_verifications', function (Blueprint $table) {
            $table->string('proof_of_address_path', 2048)->nullable()->after('selfie_path');
            $table->json('farm_photo_paths')->nullable()->after('proof_of_address_path');
            $table->string('business_name')->nullable()->change();
        });
    }

    /**
     * Reverse the migrations.
     *
     * Blank names are written as empty strings first, because the column cannot
     * return to NOT NULL while it holds nulls. The dropped columns lose only the
     * paths; the files stay on the disk.
     */
    public function down(): void
    {
        DB::table('seller_verifications')
            ->whereNull('business_name')
            ->update(['business_name' => '']);

        Schema::table('seller_verifications', function (Blueprint $table) {
            $table->string('business_name')->nullable(false)->change();
            $table->dropColumn(['proof_of_address_path', 'farm_photo_paths']);
        });
    }
};
