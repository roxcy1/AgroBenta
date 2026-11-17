<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * The mobile-safe public seller profile.
 *
 * An ordinary signed-in buyer may read this, so it carries only what a public
 * profile is allowed to disclose: display identity, an optional avatar and
 * biography, the verification decision, a barangay-level location, the account
 * creation date and the count of listings the marketplace already shows.
 *
 * Deliberately absent, and not to be added: `email`, `phone`, the raw
 * `users.location` (which may contain a street or purok), verification
 * documents and their paths, `address`, `admin_note`, reviewer identity,
 * `role`, and `seller_capability`. The administrator-facing `UserResource`
 * carries several of those and is never reused here.
 *
 * The value is the array assembled by `MarketplaceSellerService`, which owns
 * the public-profile predicate and the location projection.
 */
class MobileSellerProfileResource extends JsonResource
{
    /**
     * Transform the resource into an array.
     *
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => (int) $this['id'],
            'name' => $this['name'],
            'avatar_url' => $this['avatar_url'],
            'bio' => $this['bio'],
            'is_verified' => (bool) $this['is_verified'],
            'public_location' => $this['public_location'],
            'member_since' => $this['member_since'],
            'active_listings_count' => (int) $this['active_listings_count'],
        ];
    }
}
