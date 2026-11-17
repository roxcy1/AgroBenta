<?php

namespace App\Services\Inquiry;

use App\Enums\ActivityAction;
use App\Enums\InquiryCollectionMethod;
use App\Enums\InquiryPaymentMethod;
use App\Events\InquiryCreated;
use App\Models\Inquiry;
use App\Models\Listing;
use App\Models\User;
use App\Repositories\Inquiry\InquiryRepository;
use App\Services\ActivityLogger;
use App\Services\Messaging\MessagingService;
use App\Services\Listing\ListingReservationService;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\QueryException;
use Illuminate\Support\Collection;
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
        private readonly ListingReservationService $reservations,
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
     * The caller's active inquiries on one side, for the Messages tab.
     *
     * @return Collection<int, Inquiry>
     */
    public function activeFor(User $user, ?string $role = null): Collection
    {
        return $this->inquiries->listActiveForUser($user, $role);
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
    public function create(
        User $buyer,
        Listing $listing,
        ?string $message,
        array $preferences,
        int $requestedQuantity = 1,
    ): Inquiry
    {
        try {
            return DB::transaction(function () use (
                $buyer,
                $listing,
                $message,
                $preferences,
                $requestedQuantity,
            ): Inquiry {
                // Lock the same listing row the reservation path locks. An
                // inquiry still reserves nothing, but it validates its requested
                // quantity against an authoritative available-stock snapshot.
                $lockedListing = $this->reservations->lockForInquiry(
                    (int) $listing->getKey(),
                    $requestedQuantity,
                );

                if ((int) $lockedListing->seller_id === (int) $buyer->getKey()) {
                    abort(409, 'You cannot inquire about your own listing.');
                }

                // One inquiry per buyer per listing, whatever its status. The
                // unique index remains the final guard against concurrent writes.
                if ($this->findForBuyerAndListing($buyer, $lockedListing) !== null) {
                    abort(409, 'You have already sent an inquiry about this listing.');
                }

                $inquiry = $this->inquiries->create(
                    $buyer,
                    (int) $lockedListing->seller_id,
                    (int) $lockedListing->getKey(),
                    $message,
                    $preferences,
                    $requestedQuantity,
                );

                // Create the initial buyer→seller message inside the same
                // transaction, and notify the seller for every inquiry.
                $seller = User::findOrFail((int) $lockedListing->seller_id);
                $body = $this->buildMessageBody(
                    $buyer,
                    $lockedListing,
                    $message,
                    $preferences,
                    $requestedQuantity,
                );
                $this->messaging->sendMessage(
                    $buyer,
                    $seller,
                    $body,
                    (int) $lockedListing->getKey(),
                    true,
                );

                $this->activity->log(
                    $buyer,
                    ActivityAction::InquiryCreated,
                    sprintf(
                        'Inquiry #%d sent for listing #%d.',
                        $inquiry->getKey(),
                        $lockedListing->getKey(),
                    ),
                    [
                        'target_type' => 'inquiry',
                        'target_id' => $inquiry->getKey(),
                        'context' => [
                            'listing_id' => $lockedListing->getKey(),
                            'seller_id' => (int) $lockedListing->seller_id,
                        ],
                    ],
                );

                // Notify the seller's connected client (queued + after-commit).
                InquiryCreated::dispatch($inquiry);

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
        ?string $message,
        array $preferences,
        int $requestedQuantity,
    ): string {
        $price = $listing->asking_price !== null
            ? number_format((float) $listing->asking_price, 2)
            : 'not set';

        $option = $preferences['collection_date_option'] ?? null;
        $date = ! empty($preferences['preferred_schedule'])
            ? (string) $preferences['preferred_schedule']
            : 'not specified';

        $payment = InquiryPaymentMethod::tryFrom((string) ($preferences['payment_method'] ?? ''));
        $collection = InquiryCollectionMethod::tryFrom((string) ($preferences['collection_method'] ?? ''));

        $lines = [
            "New inquiry from {$buyer->name}.",
            "Listing: {$listing->displayLabel()}.",
            "Requested quantity: {$requestedQuantity}.",
            "Asking price: ₱{$price}.",
            'Preferred payment: '.($payment?->label() ?? 'not specified'),
            'Preferred collection: '.($collection?->label() ?? 'not specified'),
            'Collection date option: '.(
                $option === null || $option === ''
                    ? 'no preference'
                    : "$option ($date)"
            ),
            '',
            "Buyer's message:",
            $message === null || trim($message) === ''
                ? 'No additional message.'
                : trim($message),
        ];

        return implode("\n", $lines);
    }
}
