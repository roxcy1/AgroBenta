<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\DeactivateFromReportRequest;
use App\Http\Requests\Admin\DismissUserReportRequest;
use App\Http\Requests\Admin\IndexUserReportsRequest;
use App\Http\Resources\AdminUserReportResource;
use App\Models\UserReport;
use App\Services\Admin\AdminUserReportService;
use Illuminate\Http\JsonResponse;
use Symfony\Component\HttpFoundation\StreamedResponse;

class UserReportController extends Controller
{
    public function __construct(private readonly AdminUserReportService $reports)
    {
        //
    }

    public function index(IndexUserReportsRequest $request): JsonResponse
    {
        $paginator = $this->reports->listReports(
            $request->validated('status'),
            $request->validated('per_page', 15),
        );

        return response()->json([
            'success' => true,
            'data' => [
                'reports' => AdminUserReportResource::collection($paginator->items()),
                'pagination' => [
                    'current_page' => $paginator->currentPage(),
                    'last_page' => $paginator->lastPage(),
                    'per_page' => $paginator->perPage(),
                    'total' => $paginator->total(),
                ],
            ],
        ], 200);
    }

    public function show(UserReport $userReport): JsonResponse
    {
        return response()->json([
            'success' => true,
            'data' => new AdminUserReportResource(
                $this->reports->findReport((int) $userReport->getKey()),
            ),
        ], 200);
    }

    public function evidence(UserReport $userReport): StreamedResponse
    {
        return $this->reports->evidenceResponse($userReport);
    }

    public function dismiss(
        DismissUserReportRequest $request,
        UserReport $userReport,
    ): JsonResponse {
        $report = $this->reports->dismiss(
            $userReport,
            $request->user(),
            $request->validated('admin_note'),
        );

        return response()->json([
            'success' => true,
            'message' => 'Report dismissed.',
            'data' => new AdminUserReportResource($report),
        ], 200);
    }

    public function deactivate(
        DeactivateFromReportRequest $request,
        UserReport $userReport,
    ): JsonResponse {
        $report = $this->reports->deactivate(
            $userReport,
            $request->user(),
            $request->validated('reason'),
        );

        return response()->json([
            'success' => true,
            'message' => 'Report actioned and account deactivated.',
            'data' => new AdminUserReportResource($report),
        ], 200);
    }
}
