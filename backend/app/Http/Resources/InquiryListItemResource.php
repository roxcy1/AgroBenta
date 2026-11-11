<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * One active inquiry as the Messages "Inquiries" tab renders it.
 *
 * Distinct from `MobileInquiryResource` (the buyer's create response): this
 * projection is side-aware, names the counterpart, and carries the latest offer
 * so the tab can show what still needs negotiating. It deliberately omits both
 * parties' contact details.
 */
class InquiryListItemResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $viewerId = (int) $request->user()?->getAuthIdentifier();
        $isBuyer = (int) $this->buyer_id === $viewerId;
        $counterpart = $isBuyer ? $this->seller : $this->buyer;

        $listing = $this->listing;
        $photos = $listing?->photos;
        $latestOffer = $this->relationLoaded('offers')
            ? $this->offers->first()
            : null;

        return [
            'id' => $this->id,
            'role' => $isBuyer ? 'buyer' : 'seller',
            'status' => $this->status?->value,
            'listing' => $listing === null ? null : [
                'id' => $listing->id,
                'title' => trim(($listing->livestock_type ?? '').' '.($listing->breed ?? '')),
                'asking_price' => $listing->asking_price,
                'photo_url' => is_array($photos) && $photos !== []
                    ? (string) reset($photos)
                    : null,
            ],
            'counterpart' => $counterpart === null ? null : [
                'id' => $counterpart->id,
                'name' => $counterpart->name,
            ],
            'payment_method' => $this->payment_method?->value,
            'collection_method' => $this->collection_method?->value,
            'preferred_schedule' => $this->preferred_schedule?->toDateString(),
            'message' => $this->message,
            'latest_offer' => $latestOffer === null ? null : [
                'id' => $latestOffer->id,
                'status' => $latestOffer->status?->value,
                'proposed_amount' => $latestOffer->proposed_amount,
            ],
            // The seller may revise after a decline/withdrawal, but never
            // while pending and never after acceptance (server-owned rule).
            'can_make_offer' => $isBuyer
                ? false
                : $this->offers->every(
                    fn ($offer): bool => ! in_array(
                        $offer->status?->value,
                        ['pending', 'accepted'],
                        true,
                    ),
                ),
            'created_at' => $this->created_at?->toISOString(),
        ];
    }
}
