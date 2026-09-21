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
        Schema::create('listings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('seller_id')->constrained('users')->cascadeOnDelete();
            $table->string('livestock_type');
            $table->string('breed');
            $table->decimal('age_value', 5, 1)->nullable();
            $table->enum('age_unit', ['day', 'month', 'year'])->nullable();
            $table->enum('gender', ['male', 'female'])->nullable();
            $table->decimal('weight_value', 10, 2)->nullable();
            $table->enum('weight_unit', ['kg', 'lb'])->default('kg');
            $table->unsignedInteger('quantity');
            $table->decimal('asking_price', 14, 2);
            $table->string('location');
            $table->string('health_status')->nullable();
            $table->string('vaccination')->nullable();
            $table->string('short_description');
            $table->text('additional_notes')->nullable();
            $table->json('photos');
            $table->enum('status', ['draft', 'pending', 'active', 'sold', 'inactive'])->default('draft');
            $table->timestamps();

            $table->index(['seller_id']);
            $table->index(['status', 'livestock_type']);
            $table->index(['created_at']);
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('listings');
    }
};
