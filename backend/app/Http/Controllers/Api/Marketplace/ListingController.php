<?php

namespace App\Http\Controllers\Api\Marketplace;

use App\Http\Controllers\Controller;
use App\Http\Requests\Marketplace\IndexListingRequest;
use App\Http\Resources\MobileListingResource;
use App\Services\Marketplace\MarketplaceListingService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Buyer marketplace browsing.
 *
 * Read-only. This controller creates, updates and deletes nothing; every
 * response is assembled from `MobileListingResource`, never from the
 * administrator-facing `ListingResource`.
 *
 * The two responses use the two hand-rolled envelopes the Admin Web already
 * depends on: a list response with a nested `pagination` object of exactly four
 * keys (contract §3.2), and a detail response with the listing directly under
 * `data` (contract §3.1).
 */
class ListingController extends Controller
{
    public function __construct(private readonly MarketplaceListingService $listings)
    {
        //
    }

    /**
     * Browse the marketplace.
     */
    public function index(IndexListingRequest $request): JsonResponse
    {
        $minPrice = $request->validated('min_price');
        $maxPrice = $request->validated('max_price');
        $minAge = $request->validated('min_age');
        $maxAge = $request->validated('max_age');
        $minWeight = $request->validated('min_weight');
        $maxWeight = $request->validated('max_weight');

        $livestockTypes = $request->validated('livestock_type');
        $breeds = $request->validated('breed');

        $paginator = $this->listings->browseMarketplace(
            search: $request->validated('search'),
            // Multi-select filters are normalised to arrays by the request, so
            // the service only ever receives one shape.
            livestockTypes: is_array($livestockTypes) ? $livestockTypes : null,
            breeds: is_array($breeds) ? $breeds : null,
            gender: $request->validated('gender'),
            // Query-string values arrive as strings. Validation has already
            // proved they are numeric, so they are narrowed to the type the
            // service declares rather than left to implicit coercion.
            minAge: $minAge === null ? null : (float) $minAge,
            maxAge: $maxAge === null ? null : (float) $maxAge,
            minWeight: $minWeight === null ? null : (float) $minWeight,
            maxWeight: $maxWeight === null ? null : (float) $maxWeight,
            location: $request->validated('location'),
            minPrice: $minPrice === null ? null : (float) $minPrice,
            maxPrice: $maxPrice === null ? null : (float) $maxPrice,
            perPage: (int) $request->validated('per_page', 15),
        );

        return response()->json([
            'success' => true,
            'data' => [
                'listings' => MobileListingResource::collection($paginator->items()),
                'pagination' => [
                    'current_page' => $paginator->currentPage(),
                    'last_page' => $paginator->lastPage(),
                    'per_page' => $paginator->perPage(),
                    'total' => $paginator->total(),
                ],
            ],
        ], 200);
    }

    /**
     * View one listing.
     *
     * A listing the viewer may not see and a listing that does not exist both
     * produce the same 404, so a draft, pending, inactive or sold listing cannot
     * be discovered by guessing ids.
     */
    public function show(Request $request, string $listing): JsonResponse
    {
        $mobileListing = $this->listings->findMarketplaceListing(
            (int) $listing,
            (int) $request->user()->getAuthIdentifier(),
        );

        if ($mobileListing === null) {
            abort(404, 'Listing not found.');
        }

        return response()->json([
            'success' => true,
            'data' => new MobileListingResource($mobileListing),
        ], 200);
    }
}
