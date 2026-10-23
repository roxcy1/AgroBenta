<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\ListInquiriesRequest;
use App\Http\Requests\Admin\UpdateInquiryStatusRequest;
use App\Http\Resources\InquiryResource;
use App\Models\Inquiry;
use App\Services\Admin\AdminInquiryService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class InquiryController extends Controller
{
    public function __construct(private readonly AdminInquiryService $inquiries)
    {
        //
    }

    /**
     * List inquiries with optional search, filtering, and pagination.
     */
    public function index(ListInquiriesRequest $request): JsonResponse
    {
        $paginator = $this->inquiries->listInquiries(
            search: $request->validated('search'),
            status: $request->validated('status'),
            perPage: $request->validated('per_page', 15),
        );

        return response()->json([
            'success' => true,
            'data' => [
                'inquiries' => InquiryResource::collection($paginator->items()),
                'pagination' => [
                    'current_page' => $paginator->currentPage(),
                    'last_page' => $paginator->lastPage(),
                    'per_page' => $paginator->perPage(),
                    'total' => $paginator->total(),
                ],
            ],
        ], 200);
    }

    /**
     * Show a single inquiry with both parties and the listing it concerns.
     */
    public function show(Inquiry $inquiry): JsonResponse
    {
        $inquiry->load([
            'buyer:id,name,email',
            'seller:id,name,email',
            'listing:id,livestock_type,breed',
        ]);

        return response()->json([
            'success' => true,
            'data' => new InquiryResource($inquiry),
        ], 200);
    }

    /**
     * Change an inquiry's workflow status.
     */
    public function updateStatus(UpdateInquiryStatusRequest $request, Inquiry $inquiry): JsonResponse
    {
        $result = $this->inquiries->updateStatus(
            $inquiry,
            $request->user(),
            $request->validated('status'),
        );

        return response()->json([
            'success' => true,
            'message' => 'Inquiry status updated successfully.',
            'data' => new InquiryResource($result),
        ], 200);
    }

    /**
     * Delete an inquiry.
     */
    public function destroy(Request $request, Inquiry $inquiry): JsonResponse
    {
        $this->inquiries->delete($inquiry, $request->user());

        return response()->json([
            'success' => true,
            'message' => 'Inquiry deleted successfully.',
        ], 200);
    }
}
