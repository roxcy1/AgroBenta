<?php

namespace App\Services\Inquiry;

use App\Enums\ActivityAction;
use App\Enums\ListingStatus;
use App\Models\Inquiry;
use App\Models\Listing;
use App\Models\User;
use App\Repositories\Inquiry\InquiryRepository;
use App\Services\ActivityLogger;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;

/**
 * The rules for buyer inquiries and the seller's received-inquiry read.
 *
 * The repository persists the row and resolves the counterparties; this
 * service decides whether the inquiry may be created at all. The guards are
 * the same three the transaction create path applies, for the same reasons
 * ([D-15] rules 1 and 6 are the approved precedent for a buyer acting on a
 * listing — the functional documentation is otherwise silent on inquiries):
 *
 *  - the listing must be `active`, because that is the only state a buyer can
 *    reach from the marketplace (a non-active listing is a 404 on browse, so
 *    an inquiry against one is a state conflict, not a bad request);
 *  - the listing must not be the caller's own: a seller does not inquire with
 *    themselves;
 *
 * Both are 409 rather than 422: nothing about the request is malformed, the
 * listing is simply in a state where the action has no meaning.
 *
 * Creating an inquiry changes nothing else. It does not touch the listing's
 * status, does not create a transaction, and does not mark anything sold or
 * paid — an inquiry is a message of record between a buyer and a seller.
 */
class InquiryService
{
    public function __construct(
        private readonly InquiryRepository $inquiries,
        private readonly ActivityLogger $activity,
    ) {
        //
    }

    /**
     * List the inquiries received by one seller, newest first.
     *
     * A seller may see only inquiries about their own listings (functional
     * documentation section 8.2 rule 2). The scope comes from the authenticated
     * user, so there is no request value that can widen it.
     */
    public function listForSeller(User $seller, int $perPage = 15): LengthAwarePaginator
    {
        return $this->inquiries->paginateForSeller($seller, $perPage);
    }

    /**
     * Create an inquiry for the authenticated buyer against [listing].
     *
     * @param  array<string, mixed>  $preferences  The allow-listed form fields from `StoreInquiryRequest`.
     */
    public function create(User $buyer, Listing $listing, string $message, array $preferences): Inquiry
    {
        if ($listing->status !== ListingStatus::Active) {
            abort(409, 'This listing is not available for inquiries.');
        }

        if ((int) $listing->seller_id === (int) $buyer->getKey()) {
            abort(409, 'You cannot inquire about your own listing.');
        }

        return DB::transaction(function () use ($buyer, $listing, $message, $preferences): Inquiry {
            $inquiry = $this->inquiries->create(
                $buyer,
                (int) $listing->seller_id,
                (int) $listing->getKey(),
                $message,
                $preferences,
            );

            $this->activity->log(
                $buyer,
                ActivityAction::InquiryCreated,
                sprintf(
                    'Inquiry #%d sent for listing #%d.',
                    $inquiry->getKey(),
                    $listing->getKey(),
                ),
                [
                    'target_type' => 'inquiry',
                    'target_id' => $inquiry->getKey(),
                    'context' => [
                        'listing_id' => $listing->getKey(),
                        'seller_id' => (int) $listing->seller_id,
                    ],
                ],
            );

            return $inquiry;
        });
    }
}
