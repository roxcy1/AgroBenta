<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The interest form now treats its free-text message as optional. The
 * structured preferences and the generated chat card still record the
 * inquiry; an absent message is simply null.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('inquiries', function (Blueprint $table): void {
            $table->text('message')->nullable()->change();
        });
    }

    public function down(): void
    {
        Schema::table('inquiries', function (Blueprint $table): void {
            $table->text('message')->nullable(false)->change();
        });
    }
};
