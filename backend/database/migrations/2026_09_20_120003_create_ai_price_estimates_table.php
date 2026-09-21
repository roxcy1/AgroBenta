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
        Schema::create('ai_price_estimates', function (Blueprint $table) {
            $table->id();
            $table->foreignId('listing_id')->constrained()->cascadeOnDelete();
            $table->json('input_snapshot');
            $table->decimal('estimated_min', 14, 2)->nullable();
            $table->decimal('estimated_max', 14, 2)->nullable();
            $table->decimal('estimated_value', 14, 2)->nullable();
            $table->string('basis')->nullable();
            $table->timestamp('estimated_at');
            $table->timestamps();

            $table->index(['listing_id']);
            $table->index(['estimated_at']);
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('ai_price_estimates');
    }
};
