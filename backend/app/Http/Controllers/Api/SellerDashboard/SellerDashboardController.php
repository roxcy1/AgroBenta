<?php

namespace App\Http\Controllers\Api\SellerDashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\SellerDashboard\SellerDashboardRequest;
use App\Http\Resources\SellerDashboardResource;
use App\Services\SellerDashboard\SellerDashboardService;
use Illuminate\Http\JsonResponse;

class SellerDashboardController extends Controller
{
    public function __construct(
        private readonly SellerDashboardService $dashboard,
    ) {
        //
    }

    /**
     * Return summary counts for the authenticated seller.
     */
    public function show(SellerDashboardRequest $request): JsonResponse
    {
        return response()->json([
            'success' => true,
            'data' => new SellerDashboardResource(
                $this->dashboard->getDashboardForSeller($request->user()),
            ),
        ], 200);
    }
}
