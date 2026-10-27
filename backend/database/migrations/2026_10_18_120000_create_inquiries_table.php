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
        Schema::create('inquiries', function (Blueprint $table) {
            $table->id();

            // The buyer asking, and the seller being asked. Both are resolved
            // server-side from the listing on the write path, never trusted from
            // a client (see the [SEC] authority-field rule): the buyer is the
            // authenticated user and the seller is `listing.seller_id`.
            $table->foreignId('buyer_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('seller_id')->constrained('users')->cascadeOnDelete();

            // Optional and nulled rather than cascaded: an inquiry is a record
            // of contact that should outlive the listing it referred to.
            $table->foreignId('listing_id')->nullable()->constrained()->nullOnDelete();

            $table->string('subject')->nullable();
            $table->text('message');

            // Structured preferences carried by the Inquire form. All optional
            // so a plain message remains a valid inquiry.
            $table->boolean('purchase_interest')->nullable();
            $table->enum('transaction_method', ['direct_deal', 'arrange_delivery'])->nullable();
            $table->string('delivery_method')->nullable();
            $table->decimal('delivery_fee', 14, 2)->nullable();
            $table->enum('contact_method', ['in_app_message'])->nullable();
            $table->date('preferred_schedule')->nullable();

            // Administrator-facing triage state. An inquiry is created `open`
            // and never transitions from the client side.
            $table->enum('status', ['open', 'responded', 'closed'])->default('open');

            $table->timestamps();

            $table->index(['buyer_id']);
            $table->index(['seller_id']);
            $table->index(['listing_id']);
            $table->index(['status']);
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('inquiries');
    }
};
