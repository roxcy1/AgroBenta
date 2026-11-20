<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Which kinds of phone push a user wants (Profile → Notification Settings).
 *
 * At most one row per user. A user without a row receives every push, so
 * existing accounts need no backfill and a new account starts with all on.
 * Only the push is affected: every notification is still stored and listed
 * in the app.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('notification_preferences', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id')->unique()->constrained()->cascadeOnDelete();
            $table->boolean('transactions')->default(true);
            $table->boolean('messages')->default(true);
            $table->boolean('listings')->default(true);
            $table->boolean('verification')->default(true);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('notification_preferences');
    }
};
