<?php

namespace App\Http\Controllers\Api\SellerActivity;

use App\Http\Controllers\Controller;
use App\Http\Requests\SellerActivity\IndexSellerActivityRequest;
use App\Http\Resources\SellerActivityResource;
use App\Services\SellerActivity\SellerActivityService;
use Illuminate\Http\JsonResponse;

/**
 * The seller's activity feed.
 *
 * Read-only and token-scoped: the seller comes from the token and the
 * repository applies the ownership filter, so no request can widen the feed to
 * another seller or to unrelated audit entries.
 *
 * The legacy `?limit=5` shape (Seller Home) and the paginated All Activities
 * shape share the same response keys; `pagination` is additive, so the existing
 * `activities` list contract is unchanged.
 */
class SellerActivityController extends Controller
{
    public function __construct(private readonly SellerActivityService $activities)
    {
        //
    }

    /**
     * `GET /api/seller/activities`.
     */
    public function index(IndexSellerActivityRequest $request): JsonResponse
    {
        $paginator = $this->activities->paginateForSeller(
            $request->user(),
            $request->perPage(),
            $request->pageNumber(),
            $request->validated('category'),
            $request->validated('from'),
            $request->validated('to'),
        );

        return response()->json([
            'success' => true,
            'data' => [
                'activities' => SellerActivityResource::collection($paginator->items()),
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
