<?php

namespace App\Http\Controllers\Api\Marketplace;

use App\Http\Controllers\Controller;
use App\Http\Resources\PopularLivestockCategoryResource;
use App\Repositories\Marketplace\MarketplaceListingRepository;
use App\Services\Marketplace\MarketplaceListingService;
use Illuminate\Http\JsonResponse;

/**
 * The buyer Home "Popular Livestock" ranking.
 *
 * Read-only and token-scoped like the rest of the mobile marketplace. The
 * ranking is a count of genuinely completed transactions in the last 30 days,
 * grouped over the four canonical categories; it never looks at views,
 * inquiries or pending/cancelled records.
 */
class PopularLivestockController extends Controller
{
    public function __construct(private readonly MarketplaceListingService $listings)
    {
        //
    }

    /**
     * `GET /api/marketplace/popular-livestock`.
     */
    public function index(): JsonResponse
    {
        return response()->json([
            'success' => true,
            'data' => [
                'window_days' => MarketplaceListingRepository::POPULAR_WINDOW_DAYS,
                'categories' => PopularLivestockCategoryResource::collection(
                    $this->listings->popularLivestock(),
                ),
            ],
        ], 200);
    }
}
