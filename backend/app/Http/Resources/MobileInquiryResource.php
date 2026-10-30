<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * The mobile-facing shape of an inquiry: what the buyer just sent, echoed
 * back as stored.
 *
 * Deliberately narrower than the administrator's `InquiryResource`:
 *
 *  - no `buyer` / `seller` projections and **no emails** — a mobile reader is
 *    the buyer, who knows who they are, and seller contact details must not be
 *    disclosed through this projection (functional documentation §10.4);
 *  - no `status` — the workflow marker is an internal administrator bookmark
 *    (`routes/api.php`, admin block) and gates no mobile behaviour, so
 *    modelling it here would invite the client to render a state it has no
 *    business acting on;
 *
 * `listing` is echoed as the same narrow identity the transaction resource
 * carries, so the confirmation screen can name what was asked about without a
 * second request.
 */
class MobileInquiryResource extends JsonResource
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
            'collection_date_option' => $this->collection_date_option,
            'payment_method' => $this->payment_method?->value,
            'collection_method' => $this->collection_method?->value,
            'created_at' => $this->created_at?->toISOString(),
            // The conversation counterpart (seller) id, so the buyer can open
            // the exact thread from "Go to Messages".
            'conversation_counterpart_id' => $this->seller_id,
        ];
    }
}
