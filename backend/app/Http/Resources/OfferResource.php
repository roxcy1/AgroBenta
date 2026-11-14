<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * A purchase offer, in the shape the mobile client reads.
 *
 * Mirrors `Offer` on the backend. `proposed_amount` is a decimal string
 * (server-derived, never client-computed). The buyer sees the seller's
 * proposed price and terms; the seller sees the offer they made. Both see the
 * inquiry and listing context, plus the offer's lifecycle state.
 *
 * `original_terms` is the buyer's own inquiry preference at the time the offer
 * was made. The client diffs against it so the buyer can see what the seller
 * changed, without inventing a comparison the server did not send.
 */
class OfferResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $inquiry = $this->relationLoaded('inquiry') ? $this->inquiry : null;
        $listing = $this->relationLoaded('listing') ? $this->listing : null;
        $photos = $listing?->photos;

        return [
            'id' => $this->id,
            'inquiry_id' => $this->inquiry_id,
            'listing_id' => $this->listing_id,
            'seller_id' => $this->seller_id,
            'buyer_id' => $this->buyer_id,
            'proposed_amount' => $this->proposed_amount,
            'proposed_quantity' => $this->proposed_quantity,
            'proposed_pickup_date' => $this->proposed_pickup_date?->toDateString(),
            'payment_method' => $this->payment_method?->value,
            'collection_method' => $this->collection_method?->value,
            'note' => $this->note,
            'status' => $this->status?->value,
            'responded_at' => $this->responded_at?->toISOString(),
            'created_at' => $this->created_at?->toISOString(),
            'listing' => $listing === null ? null : [
                'id' => $listing->id,
                'livestock_type' => $listing->livestock_type,
                'breed' => $listing->breed,
                'asking_price' => $listing->asking_price,
                'quantity' => $listing->quantity,
                'inventory_reconciliation_required' => (bool) $listing->inventory_reconciliation_required,
                'photo_url' => is_array($photos) && $photos !== []
                    ? (string) reset($photos)
                    : null,
            ],
            'original_terms' => $inquiry === null ? null : [
                'payment_method' => $inquiry->payment_method?->value,
                'collection_method' => $inquiry->collection_method?->value,
                'pickup_date' => $inquiry->preferred_schedule?->toDateString(),
            ],
        ];
    }
}
