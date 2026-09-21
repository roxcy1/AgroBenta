<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Resources\DashboardResource;
use App\Services\DashboardService;
use Illuminate\Http\JsonResponse;

class DashboardController extends Controller
{
    public function __construct(private readonly DashboardService $dashboard)
    {
        //
    }

    /**
     * Return aggregate dashboard data for the administrator.
     */
    public function index(): JsonResponse
    {
        $data = $this->dashboard->getDashboardData();

        return response()->json([
            'success' => true,
            'data' => new DashboardResource($data),
        ], 200);
    }
}
