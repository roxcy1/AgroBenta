<?php

namespace App\Repositories\PriceSuggestion;

use App\Models\AiPriceEstimate;
use App\Models\Listing;

/**
 * Persistence for price-suggestion history. The estimate is always tied to the
 * listing resolved from the authenticated seller's ownership scope.
 */
class AiPriceEstimateRepository
{
    /**
     * @param  array<string, mixed>  $attributes
     */
    public function createForListing(Listing $listing, array $attributes): AiPriceEstimate
    {
        return $listing->aiPriceEstimates()->create($attributes);
    }
}
