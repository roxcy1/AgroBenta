<?php

namespace App\Services\Offer;

use App\Enums\ActivityAction;
use App\Enums\ListingStatus;
use App\Enums\OfferStatus;
use App\Models\Offer;
use App\Models\Transaction;
use App\Models\User;
use App\Repositories\Offer\OfferRepository;
use App\Repositories\Transaction\TransactionRepository;
use App\Services\ActivityLogger;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * The rules for what may happen to a purchase offer, and from which state.
 *
 * An offer lives inside a buyer–seller conversation and is tied to one
 * inquiry (hence one listing). Only the listing's seller may create one, and
 * only the inquiry's buyer may accept or decline it; only the creating seller
 * may withdraw it. `pending` is the only actionable state; every other state
 * is terminal.
 *
 * Accepting an offer creates exactly one `pending` transaction using the
 * agreed `proposed_amount` as `total_amount`. Transaction completion
 * (buyer confirms receipt) remains blocked by OQ-15 — the backend's
 * `POST /transactions/{id}/complete` answers 501 — so an accepted offer
 * yields a `pending` transaction that awaits that decision. This mirrors
 * functional documentation §6.4 (seller accepts, then buyer confirms receipt)
 * without inventing a completion actor.
 *
 * ## Why the write methods take an id, not a model
 *
 * A model handed in by a controller was loaded before the database
 * transaction started, so its `status` can already be stale. Each write
 * method resolves and locks the row itself, inside its transaction, from the
 * caller-scoped repository lookup. That is what makes "exactly one pending
 * offer" and "exactly one transaction per acceptance" hold under concurrent
 * requests.
 */
class OfferService
{
    public function __construct(
        private readonly OfferRepository $offers,
        private readonly TransactionRepository $transactions,
        private readonly ActivityLogger $activity,
    ) {
        //
    }

    /**
     * Create a purchase offer from the authenticated seller for an inquiry.
     *
     * Guards, in order:
     *  - the inquiry exists (locked for the duration of the transaction);
     *  - the listing exists and is `active`;
     *  - the caller is the listing's seller (an approved seller);
     *  - the inquiry belongs to that listing;
     *  - the inquiry's buyer is not the caller;
     *  - there is no existing `pending` offer for the inquiry.
     *
     * A well-formed request against an offer in the wrong state is a 409,
     * not a 422.
     */
    public function create(
        User $seller,
        int $inquiryId,
        int $listingId,
        string $proposedAmount,
        array $terms = [],
    ): Offer {
        return DB::transaction(function () use (
            $seller,
            $inquiryId,
            $listingId,
            $proposedAmount,
            $terms,
        ): Offer {
            $inquiry = $this->offers->lockInquiry($inquiryId);
            if ($inquiry === null) {
                abort(404, 'Inquiry not found.');
            }

            $listing = $this->offers->findListing($listingId);
            if ($listing === null) {
                abort(404, 'Listing not found.');
            }

            if ($listing->status !== ListingStatus::Active) {
                abort(409, 'This listing is not available for offers.');
            }

            if ((int) $listing->seller_id !== (int) $seller->getKey()) {
                abort(409, 'You may only make an offer on your own listing.');
            }

            if ((int) $inquiry->listing_id !== (int) $listing->getKey()) {
                abort(409, 'That inquiry does not belong to this listing.');
            }

            if ((int) $inquiry->buyer_id === (int) $seller->getKey()) {
                abort(409, 'You cannot make an offer on your own inquiry.');
            }

            if ($this->offers->findPendingForInquiry($inquiryId) !== null) {
                abort(409, 'This inquiry already has a pending offer.');
            }

            if ($this->offers->hasAcceptedForInquiry($inquiryId)) {
                abort(409, 'This inquiry has already been accepted.');
            }

            $offer = $this->offers->create([
                'inquiry_id' => (int) $inquiry->getKey(),
                'listing_id' => (int) $listing->getKey(),
                'seller_id' => (int) $seller->getKey(),
                'buyer_id' => (int) $inquiry->buyer_id,
                'proposed_amount' => $proposedAmount,
                'proposed_pickup_date' => $terms['proposed_pickup_date'] ?? null,
                'payment_method' => $terms['payment_method'] ?? null,
                'collection_method' => $terms['collection_method'] ?? null,
                'note' => $terms['note'] ?? null,
                'status' => OfferStatus::Pending,
            ]);

            $this->activity->log(
                $seller,
                ActivityAction::OfferCreated,
                sprintf(
                    'Offer #%d created for inquiry #%d on listing #%d.',
                    $offer->getKey(),
                    $inquiry->getKey(),
                    $listing->getKey(),
                ),
                [
                    'target_type' => 'offer',
                    'target_id' => $offer->getKey(),
                    'context' => [
                        'inquiry_id' => $inquiry->getKey(),
                        'listing_id' => $listing->getKey(),
                        'seller_id' => (int) $seller->getKey(),
                        'buyer_id' => (int) $inquiry->buyer_id,
                        'proposed_amount' => $proposedAmount,
                    ],
                ],
            );

            return $offer->load(['inquiry', 'listing']);
        });
    }

    /**
     * Accept a pending offer. Only the inquiry's buyer may accept.
     *
     * Creates exactly one `pending` transaction using the agreed
     * `proposed_amount`, inside the same database transaction as the offer
     * status change. The offer row is locked before its state is read, so a
     * concurrent acceptance cannot create a second transaction. The listing
     * row is then locked and must still be `active` with stock, exactly as for
     * a direct purchase. Lock order is offer, then listing; nothing that holds
     * the listing lock waits on an offer row.
     *
     * @return array{offer: Offer, transaction: Transaction}
     */
    public function accept(int $offerId, User $buyer): array
    {
        return DB::transaction(function () use ($offerId, $buyer): array {
            $offer = $this->offers->lockForUser($offerId, $buyer);
            if ($offer === null) {
                abort(404, 'Offer not found.');
            }

            if ((int) $offer->buyer_id !== (int) $buyer->getKey()) {
                abort(409, 'Only the buyer may accept this offer.');
            }

            if ($offer->status !== OfferStatus::Pending) {
                abort(409, 'This offer is no longer pending.');
            }

            // The offer may be days old. Re-check the listing under a row lock,
            // with the same guards a direct purchase uses, so an offer cannot
            // become a transaction on a listing that has since been sold,
            // deactivated or run out of stock. The offer stays pending when
            // this refuses, so the seller can still withdraw it.
            $listing = $this->offers->lockListing((int) $offer->listing_id);
            if ($listing === null) {
                abort(404, 'Listing not found.');
            }

            if ($listing->status !== ListingStatus::Active) {
                abort(409, 'This listing is not available for new transactions.');
            }

            if ($listing->seller === null) {
                abort(409, 'This listing is not available for new transactions.');
            }

            if ((int) $listing->quantity < 1) {
                abort(409, 'There is not enough stock for the requested quantity.');
            }

            $accepted = $this->offers->updateStatus(
                $offer,
                OfferStatus::Accepted,
            );

            $transaction = $this->transactions->createPending(
                $buyer,
                (int) $accepted->seller_id,
                (int) $accepted->listing_id,
                1,
                (string) $accepted->proposed_amount,
                (int) $accepted->getKey(),
                $accepted->payment_method?->value,
                $accepted->collection_method?->value,
                $accepted->proposed_pickup_date?->toDateString(),
            );

            $this->activity->log(
                $buyer,
                ActivityAction::OfferAccepted,
                sprintf(
                    'Offer #%d accepted; transaction #%d created.',
                    $accepted->getKey(),
                    $transaction->getKey(),
                ),
                [
                    'target_type' => 'offer',
                    'target_id' => $accepted->getKey(),
                    'context' => [
                        'offer_id' => $accepted->getKey(),
                        'transaction_id' => $transaction->getKey(),
                        'listing_id' => $accepted->listing_id,
                        'buyer_id' => $buyer->getKey(),
                        'seller_id' => (int) $accepted->seller_id,
                    ],
                ],
            );

            return [
                'offer' => $accepted,
                'transaction' => $transaction,
            ];
        });
    }

    /**
     * Decline a pending offer. Only the inquiry's buyer may decline.
     */
    public function decline(int $offerId, User $buyer): Offer
    {
        return $this->transition(
            $offerId,
            $buyer,
            'buyer',
            OfferStatus::Declined,
            ActivityAction::OfferDeclined,
            'Only the buyer may decline this offer.',
        );
    }

    /**
     * Withdraw a pending offer. Only the creating seller may withdraw.
     */
    public function withdraw(int $offerId, User $seller): Offer
    {
        return $this->transition(
            $offerId,
            $seller,
            'seller',
            OfferStatus::Withdrawn,
            ActivityAction::OfferWithdrawn,
            'Only the offering seller may withdraw this offer.',
        );
    }

    /**
     * The caller's offers, newest first.
     *
     * @return Collection<int, Offer>
     */
    public function list(
        User $user,
        ?int $inquiryId = null,
        ?int $counterpartId = null,
        ?int $listingId = null,
        ?OfferStatus $status = null,
    ): Collection {
        return $this->offers->listForUser(
            $user,
            $inquiryId,
            $counterpartId,
            $listingId,
            $status,
        );
    }

    /**
     * Transition a pending offer to a terminal state, guarded against
     * concurrent transitions and against an actor on the wrong side.
     *
     * A caller who is neither party receives 404 from the locked lookup
     * (never 403), matching the convention that a user must not learn whether
     * a foreign record exists. A party on the wrong side is a 409, because the
     * record is legitimately visible to them.
     */
    private function transition(
        int $offerId,
        User $actor,
        string $requiredParty,
        OfferStatus $status,
        ActivityAction $action,
        string $wrongPartyMessage,
    ): Offer {
        return DB::transaction(function () use (
            $offerId,
            $actor,
            $requiredParty,
            $status,
            $action,
            $wrongPartyMessage
        ): Offer {
            $offer = $this->offers->lockForUser($offerId, $actor);
            if ($offer === null) {
                abort(404, 'Offer not found.');
            }

            $requiredId = $requiredParty === 'buyer'
                ? (int) $offer->buyer_id
                : (int) $offer->seller_id;

            if ($requiredId !== (int) $actor->getKey()) {
                abort(409, $wrongPartyMessage);
            }

            if ($offer->status !== OfferStatus::Pending) {
                abort(409, 'This offer is no longer pending.');
            }

            $transitioned = $this->offers->updateStatus($offer, $status);

            $this->activity->log(
                $actor,
                $action,
                sprintf(
                    'Offer #%d %s.',
                    $transitioned->getKey(),
                    $status->value,
                ),
                [
                    'target_type' => 'offer',
                    'target_id' => $transitioned->getKey(),
                    'context' => [
                        'offer_id' => $transitioned->getKey(),
                        'listing_id' => $transitioned->listing_id,
                        'buyer_id' => $transitioned->buyer_id,
                        'seller_id' => $transitioned->seller_id,
                    ],
                ],
            );

            return $transitioned;
        });
    }
}
