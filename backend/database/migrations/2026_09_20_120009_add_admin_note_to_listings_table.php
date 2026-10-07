<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * The administrator's note on a rejected listing.
     *
     * Contract §5.4b specifies that rejecting a listing "takes an
     * `admin_note`", and the `listings` table had nowhere to put one. Nullable
     * text, like `seller_verifications.admin_note`, because a listing that was
     * approved or deactivated was never annotated — only a rejection has
     * something to explain.
     *
     * Read by the Admin Web only. The mobile resources do not carry it, so a
     * seller reading their own listing through `GET /seller/listings` does not
     * see the note: the contract specifies the field on the admin action and
     * does not state that the seller is shown it, and inventing a seller-visible
     * note would be a decision the documentation has not made.
     */
    public function up(): void
    {
        Schema::table('listings', function (Blueprint $table): void {
            $table->text('admin_note')->nullable()->after('status');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('listings', function (Blueprint $table): void {
            $table->dropColumn('admin_note');
        });
    }
};
