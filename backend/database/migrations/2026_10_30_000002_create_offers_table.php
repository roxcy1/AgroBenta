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
        Schema::create('offers', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('inquiry_id')->constrained('inquiries');
            $table->foreignId('listing_id')->constrained('listings')->cascadeOnDelete();
            $table->foreignId('seller_id')->constrained('users');
            $table->foreignId('buyer_id')->constrained('users');
            $table->decimal('proposed_amount', 14, 2);
            $table->enum('status', [
                'pending',
                'accepted',
                'declined',
                'withdrawn',
                'expired',
            ])->default('pending');
            $table->timestamp('responded_at')->nullable();
            $table->timestamps();

            $table->index(['inquiry_id']);
            $table->index(['listing_id']);
            $table->index(['seller_id']);
            $table->index(['buyer_id']);
            $table->index(['status']);
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('offers');
    }
};
