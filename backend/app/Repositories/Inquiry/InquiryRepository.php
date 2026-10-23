<?php

namespace App\Repositories\Inquiry;

use App\Enums\InquiryContactMethod;
use App\Enums\InquiryStatus;
use App\Enums\InquiryTransactionMethod;
use App\Models\Inquiry;
use App\Models\User;

/**
 * Data access for creating an inquiry.
 *
 * The three authority fields are set here, from the authenticated user and
 * the listing, rather than accepted from the request — they are the fields a
 * device must never choose ([SEC] authority-field rule):
 *
 *  - `buyer_id` is the token's user;
 *  - `seller_id` is `listing.seller_id`, so an inquiry always reaches the
 *    listing's actual owner regardless of what the client believes;
 *  - `status` is always `open`: the workflow marker is administrator-facing
 *    and has no client-side entry point (`routes/api.php`, admin block).
 */
class InquiryRepository
{
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
            'status' => InquiryStatus::Open,
        ]);
    }
}
