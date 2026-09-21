<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\ReportRequest;
use App\Http\Resources\ReportResource;
use App\Services\Admin\AdminReportService;
use Illuminate\Http\JsonResponse;

class ReportsController extends Controller
{
    public function __construct(private readonly AdminReportService $reports)
    {
        //
    }

    /**
     * Return comprehensive report data for the administrator.
     */
    public function index(ReportRequest $request): JsonResponse
    {
        $data = $this->reports->getReports(
            dateFrom: $request->validated('date_from'),
            dateTo: $request->validated('date_to'),
        );

        return response()->json([
            'success' => true,
            'data' => new ReportResource($data),
        ], 200);
    }
}
