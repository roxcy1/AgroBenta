<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Structured purchase-offer terms and the transaction snapshot they create.
 *
 * The seller proposes the price *and* the terms they can honour; the buyer
 * accepts the whole package. When accepted, the terms are copied onto the
 * transaction so a later change to the offer, the inquiry or the listing cannot
 * rewrite what was agreed.
 *
 * `transactions.offer_id` is unique: the acceptance path creates exactly one
 * transaction per offer, and the database refuses a second one even if the
 * service guard were bypassed.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('offers', function (Blueprint $table): void {
            $table->date('proposed_pickup_date')->nullable()->after('proposed_amount');
            $table->string('payment_method', 32)->nullable()->after('proposed_pickup_date');
            $table->string('collection_method', 32)->nullable()->after('payment_method');
            $table->string('note', 500)->nullable()->after('collection_method');
        });

        Schema::table('transactions', function (Blueprint $table): void {
            $table->foreignId('offer_id')
                ->nullable()
                ->unique()
                ->after('listing_id')
                ->constrained('offers')
                ->nullOnDelete();
            $table->date('pickup_date')->nullable()->after('total_amount');
            $table->string('payment_method', 32)->nullable()->after('pickup_date');
            $table->string('collection_method', 32)->nullable()->after('payment_method');
        });
    }

    public function down(): void
    {
        Schema::table('transactions', function (Blueprint $table): void {
            $table->dropConstrainedForeignId('offer_id');
            $table->dropColumn(['pickup_date', 'payment_method', 'collection_method']);
        });

        Schema::table('offers', function (Blueprint $table): void {
            $table->dropColumn([
                'proposed_pickup_date',
                'payment_method',
                'collection_method',
                'note',
            ]);
        });
    }
};
