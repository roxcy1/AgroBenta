<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\ListListingsRequest;
use App\Http\Resources\ListingResource;
use App\Services\Admin\AdminListingService;
use Illuminate\Http\JsonResponse;

class ListingController extends Controller
{
    public function __construct(private readonly AdminListingService $listings)
    {
        //
    }

    /**
     * List livestock listings with optional search, filtering, and pagination.
     */
    public function index(ListListingsRequest $request): JsonResponse
    {
        $paginator = $this->listings->listListings(
            search: $request->validated('search'),
            livestockType: $request->validated('livestock_type'),
            status: $request->validated('status'),
            perPage: $request->validated('per_page', 15),
        );

        return response()->json([
            'success' => true,
            'data' => [
                'listings' => ListingResource::collection($paginator->items()),
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
