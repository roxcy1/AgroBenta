<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * The mobile-facing shape of an inquiry as received by its seller.
 *
 * Narrower than the administrator's `InquiryResource`:
 *
 *  - `buyer` carries only an identity and display name, never an email or
 *    other contact detail (functional documentation section 10.4);
 *  - `listing` carries the same narrow identity the buyer's confirmation and
 *    the transaction resource use, and is null when the listing has since been
 *    deleted (`listings` are nulled rather than cascaded);
 *  - `status` is omitted. It is the administrator's triage bookmark, not a
 *    seller-facing workflow the mobile client may act on, and its presence
 *    would invite the client to render a state this phase does not implement.
 */
class SellerInquiryResource extends JsonResource
{
    /**
     * Transform the resource into an array.
     *
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'buyer' => $this->buyer ? [
                'id' => $this->buyer->id,
                'name' => $this->buyer->name,
            ] : null,
            'listing' => $this->listing ? [
                'id' => $this->listing->id,
                'livestock_type' => $this->listing->livestock_type,
                'breed' => $this->listing->breed,
            ] : null,
            'subject' => $this->subject,
            'message' => $this->message,
            'purchase_interest' => $this->purchase_interest,
            'transaction_method' => $this->transaction_method?->value,
            'delivery_method' => $this->delivery_method,
            'delivery_fee' => $this->delivery_fee,
            'contact_method' => $this->contact_method?->value,
            'preferred_schedule' => $this->preferred_schedule?->toDateString(),
            'created_at' => $this->created_at?->toISOString(),
        ];
    }
}
