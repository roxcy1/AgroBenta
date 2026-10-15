<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * The mobile-safe projection of a livestock listing.
 *
 * The administrator-facing `ListingResource` is not reused here. It embeds
 * `seller.email` and omits `photos`; trimming a shared resource per client is
 * how a field gets re-added for one client and silently re-exposed to the other
 * (functional documentation §10.4, contract §8.1). This resource is owned by the
 * mobile surface.
 *
 * `price_suggestion` from the contract's example shape is intentionally absent:
 * whether a buyer may see an estimate is still open (D-13) and no estimator
 * exists (GAP-10 / OQ-03). Emitting the key would encode an undecided answer.
 */
class MobileListingResource extends JsonResource
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
            'seller' => new MobileSellerResource($this->seller),
            'livestock_type' => $this->livestock_type,
            'breed' => $this->breed,
            'age_value' => $this->age_value,
            'age_unit' => $this->age_unit,
            'gender' => $this->gender,
            'weight_value' => $this->weight_value,
            'weight_unit' => $this->weight_unit,
            'quantity' => $this->quantity,
            'asking_price' => $this->asking_price,
            'location' => $this->location,
            'health_status' => $this->health_status,
            'vaccination' => $this->vaccination,
            'short_description' => $this->short_description,
            'additional_notes' => $this->additional_notes,
            'photos' => $this->photoUrls(),
            'status' => $this->status?->value,
            'admin_note' => $this->admin_note,
            'created_at' => $this->created_at?->toISOString(),
            'updated_at' => $this->updated_at?->toISOString(),
        ];
    }

    /**
     * The stored `listings.photos` JSON, projected as absolute URLs.
     *
     * The read half of the D-10 decision (functional documentation §4.5): the
     * column stores bare filenames and `Listing`'s accessor resolves each one
     * through the `listing-photos` disk's URL scheme, so what arrives here is
     * already a fetchable absolute URL — never a storage-relative path a
     * mobile client could not resolve. The schema is untouched; the column was
     * sufficient.
     *
     * The string filter is defence in depth: the model accessor only emits
     * strings, so this can only ever drop something another code path wrote
     * malformed, which is preferable to handing a client an unexpected shape.
     *
     * @return list<string>
     */
    private function photoUrls(): array
    {
        $photos = $this->resource->photos;

        if (! is_array($photos)) {
            return [];
        }

        return array_values(array_filter(
            $photos,
            static fn (mixed $photo): bool => is_string($photo),
        ));
    }
}
