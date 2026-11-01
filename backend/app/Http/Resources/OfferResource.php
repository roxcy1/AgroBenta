<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * A purchase offer, in the shape the mobile client reads.
 *
 * Mirrors `Offer` on the backend. `proposed_amount` is a decimal string
 * (server-derived, never client-computed). The buyer sees the seller's
 * proposed price; the seller sees the offer they made. Both see the inquiry
 * and listing context, plus the offer's lifecycle state.
 */
class OfferResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'inquiry_id' => $this->inquiry_id,
            'listing_id' => $this->listing_id,
            'seller_id' => $this->seller_id,
            'buyer_id' => $this->buyer_id,
            'proposed_amount' => $this->proposed_amount,
            'status' => $this->status?->value,
            'responded_at' => $this->responded_at?->toISOString(),
            'created_at' => $this->created_at?->toISOString(),
        ];
    }
}
