<?php

namespace App\Http\Controllers\Api\Report;

use App\Http\Controllers\Controller;
use App\Http\Requests\Report\StoreUserReportRequest;
use App\Http\Resources\UserReportResource;
use App\Services\UserReport\UserReportService;
use Illuminate\Http\JsonResponse;

class UserReportController extends Controller
{
    public function __construct(private readonly UserReportService $reports)
    {
        //
    }

    /**
     * File one report against another user. The reporter is the token owner.
     */
    public function store(StoreUserReportRequest $request): JsonResponse
    {
        $report = $this->reports->create(
            $request->user(),
            $request->safe()->only(['reported_user_id', 'reason', 'description']),
            $request->file('evidence'),
        );

        return response()->json([
            'success' => true,
            'message' => 'Report submitted.',
            'data' => new UserReportResource($report),
        ], 201);
    }
}
