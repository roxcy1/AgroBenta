<?php

namespace App\Repositories\Inquiry;

use App\Enums\InquiryCollectionMethod;
use App\Enums\InquiryContactMethod;
use App\Enums\InquiryPaymentMethod;
use App\Enums\InquiryStatus;
use App\Enums\InquiryTransactionMethod;
use App\Models\Inquiry;
use App\Models\User;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;

/**
 * Data access for inquiries.
 *
 * On the write path, the three authority fields are set here, from the
 * authenticated user and the listing, rather than accepted from the request -
 * they are the fields a device must never choose ([SEC] authority-field rule):
 *
 *  - `buyer_id` is the token's user;
 *  - `seller_id` is `listing.seller_id`, so an inquiry always reaches the
 *    listing's actual owner regardless of what the client believes;
 *  - `status` is always `open`: the workflow marker is administrator-facing
 *    and has no client-side entry point (`routes/api.php`, admin block).
 *
 * On the read path, the seller scope is likewise applied here in SQL, so
 * "not yours" is never a condition the controller can forget.
 */
class InquiryRepository
{
    /**
     * Paginate the inquiries received by one seller, newest first.
     *
     * The scope is the token's user, never a client-supplied id. The buyer and
     * listing projections are eager-loaded with only the columns the mobile
     * response needs: no buyer email and no listing seller details are read
     * into memory, let alone serialised.
     */
    public function paginateForSeller(User $seller, int $perPage = 15): LengthAwarePaginator
    {
        return Inquiry::query()
            ->with([
                'buyer:id,name',
                'listing:id,livestock_type,breed',
            ])
            ->where('seller_id', $seller->getKey())
            // A total order, so two inquiries written in the same second cannot
            // appear on two pages at once.
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->paginate($perPage);
    }

    /**
     * Count the inquiries received by one seller.
     *
     * The scope is the token's user, never a client-supplied id.
     */
    public function countForSeller(User $seller): int
    {
        return Inquiry::query()
            ->where('seller_id', $seller->getKey())
            ->count();
    }

    /**
     * Find the inquiry one buyer already sent about one listing.
     *
     * The buyer is the token's user and the listing is the route's listing, so
     * the lookup cannot be widened to another buyer's records. A listing that
     * has since been deleted nulls `listing_id` and therefore no longer matches
     * - which is correct: a new inquiry about a different listing is a different
     * conversation.
     *
     * Newest first because the unique index below is the real guarantee; this
     * method must stay useful even if a database predates it and still holds a
     * duplicate pair.
     */
    public function findForBuyerAndListing(User $buyer, int $listingId): ?Inquiry
    {
        return Inquiry::query()
            ->with(['listing:id,livestock_type,breed'])
            ->where('buyer_id', $buyer->getKey())
            ->where('listing_id', $listingId)
            ->orderByDesc('id')
            ->first();
    }

    /**
     * Persist a new inquiry.
     *
     * @param  array<string, mixed>  $preferences  The allow-listed form fields from `StoreInquiryRequest`.
     */
    public function create(
        User $buyer,
        int $sellerId,
        int $listingId,
        string $message,
        array $preferences,
    ): Inquiry {
        return Inquiry::query()->create([
            'buyer_id' => $buyer->getKey(),
            'seller_id' => $sellerId,
            'listing_id' => $listingId,
            'subject' => $preferences['subject'] ?? null,
            'message' => $message,
            'purchase_interest' => $preferences['purchase_interest'] ?? null,
            'transaction_method' => isset($preferences['transaction_method'])
                ? InquiryTransactionMethod::from($preferences['transaction_method'])
                : null,
            'delivery_method' => $preferences['delivery_method'] ?? null,
            'delivery_fee' => $preferences['delivery_fee'] ?? null,
            'contact_method' => isset($preferences['contact_method'])
                ? InquiryContactMethod::from($preferences['contact_method'])
                : null,
            'preferred_schedule' => $preferences['preferred_schedule'] ?? null,
            'payment_method' => isset($preferences['payment_method'])
                ? InquiryPaymentMethod::from($preferences['payment_method'])
                : null,
            'collection_method' => isset($preferences['collection_method'])
                ? InquiryCollectionMethod::from($preferences['collection_method'])
                : null,
            'collection_date_option' => $preferences['collection_date_option'] ?? null,
            'status' => InquiryStatus::Open,
        ]);
    }
}
