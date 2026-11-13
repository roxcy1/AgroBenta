<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('seller_verifications', function (Blueprint $table) {
            $table->string('government_id_type', 64)->nullable()->after('id_document_ref');
            $table->string('government_id_description', 255)->nullable()->after('government_id_type');
            $table->boolean('has_no_back_image')->nullable()->after('government_id_description');
            $table->string('id_document_front_path', 2048)->nullable()->after('id_document_path');
            $table->string('id_document_back_path', 2048)->nullable()->after('id_document_front_path');
        });
    }

    public function down(): void
    {
        Schema::table('seller_verifications', function (Blueprint $table) {
            $table->dropColumn([
                'government_id_type',
                'government_id_description',
                'has_no_back_image',
                'id_document_front_path',
                'id_document_back_path',
            ]);
        });
    }
};
