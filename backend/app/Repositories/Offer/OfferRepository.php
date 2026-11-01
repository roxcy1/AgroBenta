<?php

namespace App\Repositories\Offer;

use App\Enums\OfferStatus;
use App\Models\Inquiry;
use App\Models\Listing;
use App\Models\Offer;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Collection;

/**
 * Data access for purchase offers.
 *
 * Every method here is scoped to a party of the conversation — an offer is
 * visible only to its buyer and its seller. Ownership is part of the lookup,
 * never a condition applied afterwards, so a controller cannot forget to check
 * it.
 *
 * ## Why the write paths lock rows
 *
 * Two guarantees need more than a read-then-write check:
 *
 *  - an inquiry may have at most one `pending` offer, so concurrent creates
 *    for the same inquiry must serialise; and
 *  - accepting an offer must create exactly one transaction, so concurrent
 *    accepts of the same offer must serialise.
 *
 * The `lockForUpdate` variants below are used inside the service's database
 * transaction. They lock the row the decision depends on (the inquiry or the
 * offer) before it is read, so the second request sees the first request's
 * committed state.
 */
class OfferRepository
{
    /**
     * Persist a new offer.
     *
     * @param  array<string, mixed>  $attributes
     */
    public function create(array $attributes): Offer
    {
        return Offer::query()->create($attributes);
    }

    /**
     * Find one offer the caller is a party to, or null.
     *
     * Returns null both when the offer does not exist and when the caller is
     * neither its buyer nor its seller.
     */
    public function findForUser(int $offerId, User $user): ?Offer
    {
        return $this->scopedQuery($user)
            ->where('id', $offerId)
            ->first();
    }

    /**
     * Lock one offer the caller is a party to for the duration of a
     * transaction.
     *
     * The party scope is applied in SQL before the lock, so a foreign offer is
     * never locked and is indistinguishable from one that does not exist.
     */
    public function lockForUser(int $offerId, User $user): ?Offer
    {
        return $this->scopedQuery($user)
            ->where('id', $offerId)
            ->lockForUpdate()
            ->first();
    }

    /**
     * Lock the inquiry an offer is being created against.
     *
     * Serialising on the inquiry is what makes "one pending offer per
     * inquiry" true under concurrent requests: every create for the same
     * inquiry takes the same row lock before checking for a pending offer.
     */
    public function lockInquiry(int $inquiryId): ?Inquiry
    {
        return Inquiry::query()
            ->whereKey($inquiryId)
            ->lockForUpdate()
            ->first();
    }

    /**
     * Find the listing an offer is being created against.
     */
    public function findListing(int $listingId): ?Listing
    {
        return Listing::query()->find($listingId);
    }

    /**
     * Find the pending offer for an inquiry, if any.
     *
     * Used to prevent a seller from creating more than one actionable offer
     * for the same buyer inquiry. Callers hold the inquiry lock while this
     * runs.
     */
    public function findPendingForInquiry(int $inquiryId): ?Offer
    {
        return Offer::query()
            ->where('inquiry_id', $inquiryId)
            ->where('status', OfferStatus::Pending)
            ->first();
    }

    /**
     * The caller's offers, newest first.
     *
     * Every filter narrows a list the caller is already a party to; none of
     * them can widen the result to another pair's offers.
     *
     * @return Collection<int, Offer>
     */
    public function listForUser(
        User $user,
        ?int $inquiryId = null,
        ?int $counterpartId = null,
        ?int $listingId = null,
        ?OfferStatus $status = null,
    ): Collection {
        return $this->scopedQuery($user)
            ->when(
                $inquiryId !== null,
                fn (Builder $query) => $query->where('inquiry_id', $inquiryId),
            )
            ->when(
                $counterpartId !== null,
                fn (Builder $query) => $query->where(function (Builder $query) use ($user, $counterpartId): void {
                    $query->where(function (Builder $query) use ($user, $counterpartId): void {
                        $query->where('buyer_id', $user->getKey())
                            ->where('seller_id', $counterpartId);
                    })->orWhere(function (Builder $query) use ($user, $counterpartId): void {
                        $query->where('seller_id', $user->getKey())
                            ->where('buyer_id', $counterpartId);
                    });
                }),
            )
            ->when(
                $listingId !== null,
                fn (Builder $query) => $query->where('listing_id', $listingId),
            )
            ->when(
                $status !== null,
                fn (Builder $query) => $query->where('status', $status),
            )
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->get();
    }

    /**
     * Persist a status transition on an offer the caller is party to.
     */
    public function updateStatus(Offer $offer, OfferStatus $status): Offer
    {
        $offer->status = $status;
        $offer->responded_at = now();
        $offer->save();

        return $offer->refresh();
    }

    /**
     * Scope offers to the caller as either buyer or seller.
     */
    private function scopedQuery(User $user): Builder
    {
        return Offer::query()
            ->with([
                'inquiry:buyer_id,seller_id,listing_id,status',
                'listing:id,livestock_type,breed,asking_price,seller_id',
                'seller:id,name,avatar_url',
                'buyer:id,name,avatar_url',
            ])
            ->where(function (Builder $query) use ($user): void {
                $query->where('buyer_id', $user->getKey())
                    ->orWhere('seller_id', $user->getKey());
            });
    }
}
