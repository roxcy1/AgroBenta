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
            'photos' => $this->photoPaths(),
            'status' => $this->status?->value,
            'created_at' => $this->created_at?->toISOString(),
            'updated_at' => $this->updated_at?->toISOString(),
        ];
    }

    /**
     * The stored `listings.photos` JSON, normalised to a flat list of strings.
     *
     * The column already holds a JSON array of photo paths and the schema is
     * explicitly not to be changed in order to expose it (functional
     * documentation §4.5). Values are therefore returned exactly as stored.
     *
     * No URL is synthesised: no upload endpoint writes to this column, no
     * storage disk is bound to it and no URL scheme has been decided (OQ-09 /
     * D-10). Prefixing a base URL would invent a storage mechanism this phase
     * is not permitted to create. The `photos.*` write contract is a list of
     * strings, so non-string entries are dropped rather than surfaced as an
     * unexpected shape to the client.
     *
     * @return list<string>
     */
    private function photoPaths(): array
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
