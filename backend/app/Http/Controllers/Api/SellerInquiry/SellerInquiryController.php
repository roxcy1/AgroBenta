<?php

namespace App\Http\Controllers\Api\SellerInquiry;

use App\Http\Controllers\Controller;
use App\Http\Requests\Inquiry\IndexSellerInquiryRequest;
use App\Http\Resources\SellerInquiryResource;
use App\Services\Inquiry\InquiryService;
use Illuminate\Http\JsonResponse;

/**
 * The inquiries a seller has received.
 *
 * Read-only in this phase. The seller is always the token's user - never a
 * query parameter - and the repository applies that scope in SQL, so one
 * seller cannot read another's inquiries. The response uses
 * `SellerInquiryResource`, which carries the buyer's identity but no contact
 * details and no administrator-facing status.
 */
class SellerInquiryController extends Controller
{
    public function __construct(private readonly InquiryService $inquiries)
    {
        //
    }

    /**
     * List the authenticated seller's received inquiries, newest first.
     */
    public function index(IndexSellerInquiryRequest $request): JsonResponse
    {
        $paginator = $this->inquiries->listForSeller(
            seller: $request->user(),
            perPage: (int) $request->validated('per_page', 15),
        );

        return response()->json([
            'success' => true,
            'data' => [
                'inquiries' => SellerInquiryResource::collection($paginator->items()),
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
