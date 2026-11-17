<?php

namespace App\Http\Controllers\Api\Marketplace;

use App\Http\Controllers\Controller;
use App\Http\Requests\Marketplace\IndexSellerPublicListingRequest;
use App\Http\Resources\MobileListingResource;
use App\Http\Resources\MobileSellerProfileResource;
use App\Services\Marketplace\MarketplaceSellerService;
use Illuminate\Http\JsonResponse;

/**
 * The public seller profile behind the buyer marketplace.
 *
 * Read-only. Both responses resolve the seller from the route id through
 * [MarketplaceSellerService], which owns the public-profile predicate, so a
 * missing, soft-deleted or non-public account produces the same 404 — seller
 * existence is never disclosed by a different status code.
 *
 * The listing page deliberately reuses `MobileListingResource` and the
 * hand-rolled `{listings, pagination}` envelope rather than inventing a second
 * buyer-facing listing shape.
 */
class SellerProfileController extends Controller
{
    public function __construct(private readonly MarketplaceSellerService $sellers)
    {
        //
    }

    /**
     * `GET /api/marketplace/sellers/{seller}`.
     */
    public function show(string $seller): JsonResponse
    {
        $profile = $this->sellers->profile((int) $seller);

        if ($profile === null) {
            abort(404, 'Seller not found.');
        }

        return response()->json([
            'success' => true,
            'data' => new MobileSellerProfileResource($profile),
        ], 200);
    }

    /**
     * `GET /api/marketplace/sellers/{seller}/listings`.
     */
    public function listings(IndexSellerPublicListingRequest $request, string $seller): JsonResponse
    {
        $paginator = $this->sellers->listingsFor(
            (int) $seller,
            search: $request->validated('search'),
            livestockType: $request->validated('livestock_type'),
            sort: (string) $request->validated('sort', 'newest'),
            perPage: (int) $request->validated('per_page', 15),
        );

        if ($paginator === null) {
            abort(404, 'Seller not found.');
        }

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
}
