<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Firebase Cloud Messaging registration tokens, one row per phone.
 *
 * Each row belongs to the Sanctum token of the session that registered it.
 * Deleting that access token (logout, or a password reset revoking every
 * token) deletes the row through the foreign key, so a signed-out phone stops
 * receiving pushes without a separate unregister call.
 *
 * `token` is unique: when a phone signs in to another account, its row moves
 * to that account instead of pushing to both.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('device_tokens', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->foreignId('personal_access_token_id')
                ->constrained('personal_access_tokens')
                ->cascadeOnDelete();
            $table->string('token', 512)->unique();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('device_tokens');
    }
};
