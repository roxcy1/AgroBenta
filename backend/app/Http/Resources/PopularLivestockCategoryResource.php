<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * One ranked livestock category on Buyer Home.
 *
 * The row comes from `MarketplaceListingRepository::popularLivestock()` as a
 * plain array: category, completed-sale count inside the 30-day window, and one
 * representative listing photo. No seller or listing identity is exposed here —
 * the section is a category summary, not a listing list.
 */
class PopularLivestockCategoryResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'livestock_type' => $this['livestock_type'],
            'completed_sales' => (int) $this['completed_sales'],
            'photo_url' => $this['photo_url'],
        ];
    }
}
