<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * The administrator-facing projection of a livestock listing.
 *
 * Admin-oriented by design, and deliberately not the mobile projection: it
 * embeds the seller's email address and carries `admin_note`, neither of which
 * belongs in a marketplace or seller response (functional documentation §10.4,
 * contract §8.1). `MobileListingResource` is a separate class rather than a
 * trimmed copy of this one, because a shared resource gets fields re-added for
 * one client and silently re-exposed to the other.
 */
class ListingResource extends JsonResource
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
            'seller' => [
                'id' => $this->seller->id,
                'name' => $this->seller->name,
                'email' => $this->seller->email,
            ],
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
            'status' => $this->status?->value,
            // Administrator-only: the reason a moderator gave when rejecting
            // this listing. Never present on `MobileListingResource`, so a
            // seller reading their own listing does not receive it.
            'admin_note' => $this->admin_note,
            'created_at' => $this->created_at?->toISOString(),
            'updated_at' => $this->updated_at?->toISOString(),
        ];
    }
}
