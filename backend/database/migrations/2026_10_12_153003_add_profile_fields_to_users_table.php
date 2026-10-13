<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Adds the optional profile fields the mobile Profile screen reads and writes.
 *
 * Every column is nullable: an account created by mobile registration has only
 * name, email and password, and nothing in the contract requires a phone number
 * or a location to trade. Adding them here rather than in the original
 * create_users_table migration keeps the history honest — the columns did not
 * exist when accounts were first created.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->string('phone', 32)->nullable()->after('email');
            $table->string('location', 191)->nullable()->after('phone');
            $table->string('avatar_url', 2048)->nullable()->after('location');
            $table->text('bio')->nullable()->after('avatar_url');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->dropColumn(['phone', 'location', 'avatar_url', 'bio']);
        });
    }
};