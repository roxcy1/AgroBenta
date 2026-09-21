<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\ListActivitiesRequest;
use App\Http\Resources\ActivityResource;
use App\Services\Admin\AdminActivityService;
use Illuminate\Http\JsonResponse;

class ActivityController extends Controller
{
    public function __construct(private readonly AdminActivityService $activities)
    {
        //
    }

    /**
     * List activities with optional search, filtering, and pagination.
     */
    public function index(ListActivitiesRequest $request): JsonResponse
    {
        $paginator = $this->activities->listActivities(
            search: $request->validated('search'),
            action: $request->validated('action'),
            userId: $request->validated('user_id'),
            dateFrom: $request->validated('date_from'),
            dateTo: $request->validated('date_to'),
            perPage: $request->validated('per_page', 15),
        );

        return response()->json([
            'success' => true,
            'data' => [
                'activities' => ActivityResource::collection($paginator->items()),
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
