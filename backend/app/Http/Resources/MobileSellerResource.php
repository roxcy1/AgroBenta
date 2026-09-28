<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * The marketplace-safe projection of a seller.
 *
 * `ListingResource` embeds `seller.email` because it was written for the
 * administrator view. Reusing it for a marketplace response would hand every
 * seller's email address to every marketplace reader, which the approved
 * security requirements forbid (functional documentation §10.4, contract §8.1).
 *
 * Identity and display name are the only seller fields a marketplace reader
 * needs. Contact details are deliberately absent rather than hidden, and this
 * resource is not a base for the admin resource to trim.
 */
class MobileSellerResource extends JsonResource
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
            'name' => $this->name,
        ];
    }
}
