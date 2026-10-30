<?php

namespace App\Services\Inquiry;

use App\Enums\ActivityAction;
use App\Enums\ListingStatus;
use App\Models\Inquiry;
use App\Models\Listing;
use App\Models\User;
use App\Repositories\Inquiry\InquiryRepository;
use App\Services\ActivityLogger;
use App\Services\Messaging\MessagingService;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\QueryException;
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
 *  - the buyer may have only one inquiry per listing, whatever its status. A
 *    second attempt is a 409 rather than a 422: the request is well formed,
 *    the conversation already exists.
 *
 * Both listing guards are 409 rather than 422: nothing about the request is
 * malformed, the listing is simply in a state where the action has no meaning.
 * The duplicate guard is enforced twice — a lookup before the insert and the
 * `inquiries_buyer_id_listing_id_unique` index — so two concurrent requests
 * cannot both win. A unique violation is translated to the same 409 instead of
 * surfacing as a 500.
 *
 * Creating an inquiry also creates the initial buyer→seller message and fires
 * a `NewInquiry` notification, all inside one database transaction. A
 * duplicate inquiry is refused before any message is written, so no duplicate
 * notification can result.
 */
class InquiryService
{
    public function __construct(
        private readonly InquiryRepository $inquiries,
        private readonly ActivityLogger $activity,
        private readonly MessagingService $messaging,
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
     * The inquiry one buyer already sent about one listing, or `null`.
     *
     * Buyer-scoped: the buyer is the token and the listing is the route's
     * listing, so this cannot read another buyer's records. The listing's
     * status is deliberately not checked here - the question is "did I already
     * ask?", not "may I ask now?", and the form only opens from an active
     * listing anyway.
     */
    public function findForBuyerAndListing(User $buyer, Listing $listing): ?Inquiry
    {
        return $this->inquiries->findForBuyerAndListing(
            $buyer,
            (int) $listing->getKey(),
        );
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

        // One inquiry per buyer per listing, whatever its status. This lookup
        // answers the ordinary repeat; the unique index below answers the race
        // between two requests that both pass it.
        if ($this->findForBuyerAndListing($buyer, $listing) !== null) {
            abort(409, 'You have already sent an inquiry about this listing.');
        }

        try {
            return DB::transaction(function () use ($buyer, $listing, $message, $preferences): Inquiry {
                $inquiry = $this->inquiries->create(
                    $buyer,
                    (int) $listing->seller_id,
                    (int) $listing->getKey(),
                    $message,
                    $preferences,
                );

                // Create the initial buyer→seller message inside the same
                // transaction, and notify the seller for every inquiry.
                $seller = User::findOrFail((int) $listing->seller_id);
                $body = $this->buildMessageBody($buyer, $listing, $message, $preferences);
                $this->messaging->sendMessage(
                    $buyer,
                    $seller,
                    $body,
                    (int) $listing->getKey(),
                    true,
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
        } catch (QueryException $exception) {
            // A concurrent request inserted the same pair between the lookup
            // and this insert. The row now exists, so this is the same 409 as
            // an ordinary repeat - never a 500 leaking a database error.
            if ($this->findForBuyerAndListing($buyer, $listing) !== null) {
                abort(409, 'You have already sent an inquiry about this listing.');
            }

            throw $exception;
        }
    }

    /**
     * Build the structured initial message body for the buyer→seller thread.
     *
     * Contains the listing title/price, the buyer's payment and collection
     * preferences, the preferred collection date/option, and the buyer's
     * additional message.
     *
     * @param  array<string, mixed>  $preferences
     */
    private function buildMessageBody(
        User $buyer,
        Listing $listing,
        string $message,
        array $preferences,
    ): string {
        $price = $listing->asking_price !== null
            ? number_format((float) $listing->asking_price, 2)
            : 'not set';

        $option = $preferences['collection_date_option'] ?? null;
        $date = ! empty($preferences['preferred_schedule'])
            ? (string) $preferences['preferred_schedule']
            : 'not specified';

        $lines = [
            "New inquiry from {$buyer->name}.",
            "Listing: {$listing->displayLabel()}.",
            "Asking price: ₱{$price}.",
            "Preferred payment: " . ($preferences['payment_method'] ?? 'not specified'),
            "Preferred collection: " . ($preferences['collection_method'] ?? 'not specified'),
            "Collection date option: $option ($date)",
            '',
            "Buyer's message:",
            $message,
        ];

        return implode("\n", $lines);
    }
}
