<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     *
     * Government IDs and selfies are stored as disk-relative paths on the
     * private `seller-verification-documents` disk. No URL is ever stored: a
     * public URL would defeat the access control the streaming endpoints add.
     *
     * Both columns are nullable because records created before document
     * submission existed must remain readable. A new submission is refused
     * unless both files were staged first, so null means legacy, not "optional".
     */
    public function up(): void
    {
        Schema::table('seller_verifications', function (Blueprint $table) {
            $table->string('id_document_path', 2048)->nullable()->after('id_document_ref');
            $table->string('selfie_path', 2048)->nullable()->after('id_document_path');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('seller_verifications', function (Blueprint $table) {
            $table->dropColumn(['id_document_path', 'selfie_path']);
        });
    }
};
