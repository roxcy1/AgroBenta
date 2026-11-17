<?php

namespace App\Http\Requests\Marketplace;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Query parameters for a public seller's listing page.
 *
 * The page supports the same search vocabulary as the buyer marketplace —
 * `search` over the listing name fields and an exact `livestock_type` — plus a
 * documented ordering. All three are applied in SQL over the seller's whole
 * visible inventory, so they page correctly rather than filtering only the
 * records the device has already loaded.
 *
 * Ownership is fixed by the route's `{seller}` selector, gated by the service.
 * `seller_id` and `status` are refused rather than silently ignored, matching
 * the marketplace list — a client that tries to re-scope or re-status this read
 * has a bug worth surfacing.
 */
class IndexSellerPublicListingRequest extends FormRequest
{
    public function authorize(): bool
    {
        // The route is `auth:sanctum` + `ability:mobile`. The seller selector is
        // resolved and checked by MarketplaceSellerService.
        return true;
    }

    /**
     * @return array<string, list<string>>
     */
    public function rules(): array
    {
        return [
            'search' => ['nullable', 'string', 'max:255'],
            'livestock_type' => ['nullable', 'string', 'max:255'],
            'sort' => ['nullable', 'in:newest,oldest,price_asc,price_desc'],
            'page' => ['nullable', 'integer', 'min:1'],
            'per_page' => ['nullable', 'integer', 'between:1,50'],

            'seller_id' => ['prohibited'],
            'status' => ['prohibited'],
            'user_id' => ['prohibited'],
        ];
    }
}
