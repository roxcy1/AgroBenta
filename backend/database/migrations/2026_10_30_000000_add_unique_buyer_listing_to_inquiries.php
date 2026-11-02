<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * One inquiry per buyer per listing, whatever its status.
     *
     * The service checks first and returns a 409; this index is what makes the
     * rule true under two concurrent requests, where both lookups can miss.
     *
     * `listing_id` is nullable (`nullOnDelete`), and SQL treats NULLs as
     * distinct, so an inquiry whose listing was deleted does not block a new
     * inquiry about a different listing.
     *
     * Before this migration nothing stopped a buyer from sending several
     * inquiries about one listing, so an existing database can hold duplicates,
     * and adding the unique index to such a table fails with a duplicate-entry
     * error. They are resolved first, without deleting anything.
     */
    public function up(): void
    {
        $this->detachDuplicateInquiries();

        Schema::table('inquiries', function (Blueprint $table): void {
            $table->unique(
                ['buyer_id', 'listing_id'],
                'inquiries_buyer_id_listing_id_unique',
            );
        });
    }

    /**
     * For each buyer and listing, the earliest inquiry keeps its listing and any
     * later ones are detached from it.
     *
     * Detached inquiries are kept, with their message and status: `listing_id`
     * is nullable, which is the state a deleted listing already leaves behind,
     * and SQL treats NULLs as distinct, so they no longer collide. Deleting a
     * buyer's message to satisfy an index would lose data the functional
     * documentation says must stay readable (section 12.2). The earliest is the
     * one kept because it is the conversation the service now treats as "the"
     * inquiry for that listing.
     */
    private function detachDuplicateInquiries(): void
    {
        $groups = DB::table('inquiries')
            ->select('buyer_id', 'listing_id', DB::raw('MIN(id) as keep_id'))
            ->whereNotNull('listing_id')
            ->groupBy('buyer_id', 'listing_id')
            ->havingRaw('COUNT(*) > 1')
            ->get();

        foreach ($groups as $group) {
            $detached = DB::table('inquiries')
                ->where('buyer_id', $group->buyer_id)
                ->where('listing_id', $group->listing_id)
                ->where('id', '<>', $group->keep_id)
                ->update(['listing_id' => null]);

            Log::warning(sprintf(
                'Unique inquiry index: kept inquiry #%d for buyer #%d on listing #%d and detached %d duplicate(s) from the listing.',
                $group->keep_id,
                $group->buyer_id,
                $group->listing_id,
                $detached,
            ));
        }
    }

    /**
     * Reverse the migrations.
     *
     * Dropping the index does not re-attach inquiries detached by `up()`.
     */
    public function down(): void
    {
        Schema::table('inquiries', function (Blueprint $table): void {
            $table->dropUnique('inquiries_buyer_id_listing_id_unique');
        });
    }
};
