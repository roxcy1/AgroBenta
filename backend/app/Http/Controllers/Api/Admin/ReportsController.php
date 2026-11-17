<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\ReportRequest;
use App\Http\Resources\ReportResource;
use App\Services\Admin\AdminReportExportService;
use App\Services\Admin\AdminReportService;
use Illuminate\Http\JsonResponse;
use Symfony\Component\HttpFoundation\StreamedResponse;

class ReportsController extends Controller
{
    public function __construct(
        private readonly AdminReportService $reports,
        private readonly AdminReportExportService $exports,
    ) {
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

    /**
     * Download the records behind one report section as CSV.
     *
     * This writes one row per stored record created inside the selected range,
     * not the aggregates shown on the report screen. The dataset is constrained
     * by the route, so this method only ever receives a known value.
     */
    public function export(ReportRequest $request, string $dataset): StreamedResponse
    {
        $dateFrom = $request->validated('date_from');
        $dateTo = $request->validated('date_to');

        return response()->streamDownload(
            function () use ($dataset, $dateFrom, $dateTo): void {
                $handle = fopen('php://output', 'w');

                $this->exports->write($dataset, $dateFrom, $dateTo, $handle);

                fclose($handle);
            },
            $this->exports->filename($dataset, $dateFrom, $dateTo),
            ['Content-Type' => 'text/csv; charset=UTF-8'],
        );
    }
}
