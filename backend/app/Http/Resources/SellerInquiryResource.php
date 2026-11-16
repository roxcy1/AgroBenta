<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * The mobile-facing shape of an inquiry as received by its seller.
 *
 * Deliberately narrow:
 *
 *  - `buyer` carries only an identity and display name, never an email or
 *    other contact detail (functional documentation section 10.4);
 *  - `listing` carries the same narrow identity the buyer's confirmation and
 *    the transaction resource use, and is null when the listing has since been
 *    deleted (`listings` are nulled rather than cascaded);
 *  - `status` is omitted. It is an internal triage bookmark (no administrator
 *    route sets it any more), not a seller-facing workflow the mobile client
 *    may act on, and its presence would invite the client to render a state
 *    this phase does not implement.
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
        // The accessor is read once: `reset()` takes its argument by
        // reference, so `reset($model->photos)` fails on the overloaded
        // property. Same rule in every resource that reads a photo.
        $listing = $this->listing;
        $photos = $listing?->photos;

        return [
            'id' => $this->id,
            'requested_quantity' => $this->requested_quantity,
            'buyer' => $this->buyer ? [
                'id' => $this->buyer->id,
                'name' => $this->buyer->name,
            ] : null,
            'listing' => $listing ? [
                'id' => $listing->id,
                'livestock_type' => $listing->livestock_type,
                'breed' => $listing->breed,
                'asking_price' => $listing->asking_price,
                'quantity' => $listing->quantity,
                'total_quantity' => $listing->inventory_reconciliation_required
                    ? null
                    : $listing->total_quantity,
                'inventory_reconciliation_required' => (bool) $listing->inventory_reconciliation_required,
                'photo_url' => is_array($photos) && $photos !== []
                    ? (string) reset($photos)
                    : null,
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
            // The server owns the rule, so the client only renders it: an
            // offer is allowed while the inquiry is open, nothing is pending
            // and nothing has been accepted (acceptance is permanent).
            'can_make_offer' => $this->canMakeOffer(),
        ];
    }

    /**
     * Whether this inquiry may still receive an offer from its seller.
     */
    private function canMakeOffer(): bool
    {
        $status = $this->status?->value;

        if ($status !== 'open') {
            return false;
        }

        $listing = $this->listing;
        if ($listing === null ||
            $listing->status?->value !== 'active' ||
            $listing->inventory_reconciliation_required ||
            (int) $listing->quantity < 1) {
            return false;
        }

        $offers = $this->relationLoaded('offers') ? $this->offers : collect();

        return ! $offers->contains(
            fn ($offer): bool => in_array(
                $offer->status?->value,
                ['pending', 'accepted'],
                true,
            ),
        );
    }
}
