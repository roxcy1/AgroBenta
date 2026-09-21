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
        Schema::table('users', function (Blueprint $table) {
            $table->enum('role', ['user', 'admin'])->default('user')->after('email_verified_at');
            $table->enum('seller_capability', ['buyer', 'seller'])->default('buyer')->after('role');

            $table->index('role');
            $table->index('seller_capability');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropIndex(['role']);
            $table->dropIndex(['seller_capability']);
            $table->dropColumn(['role', 'seller_capability']);
        });
    }
};
