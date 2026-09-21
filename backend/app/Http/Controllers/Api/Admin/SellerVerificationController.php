<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\ListSellerVerificationsRequest;
use App\Http\Requests\Admin\ReviewSellerVerificationRequest;
use App\Http\Resources\SellerVerificationResource;
use App\Models\SellerVerification;
use App\Services\Admin\AdminSellerVerificationService;
use Illuminate\Http\JsonResponse;

class SellerVerificationController extends Controller
{
    public function __construct(private readonly AdminSellerVerificationService $verifications)
    {
        //
    }

    /**
     * List seller verification requests with optional search, filtering, and pagination.
     */
    public function index(ListSellerVerificationsRequest $request): JsonResponse
    {
        $paginator = $this->verifications->listVerifications(
            search: $request->validated('search'),
            status: $request->validated('status'),
            perPage: $request->validated('per_page', 15),
        );

        return response()->json([
            'success' => true,
            'data' => [
                'verifications' => SellerVerificationResource::collection($paginator->items()),
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
     * Show a single seller verification request.
     */
    public function show(SellerVerification $sellerVerification): JsonResponse
    {
        $sellerVerification->load(['seller:id,name,email', 'reviewer:id,name']);

        return response()->json([
            'success' => true,
            'data' => new SellerVerificationResource($sellerVerification),
        ], 200);
    }

    /**
     * Approve a seller verification request.
     */
    public function approve(SellerVerification $sellerVerification, ReviewSellerVerificationRequest $request): JsonResponse
    {
        $result = $this->verifications->approve(
            $sellerVerification,
            $request->user()->id,
            $request->validated('admin_note'),
        );

        return response()->json([
            'success' => true,
            'message' => 'Seller verification approved successfully.',
            'data' => new SellerVerificationResource($result),
        ], 200);
    }

    /**
     * Reject a seller verification request.
     */
    public function reject(SellerVerification $sellerVerification, ReviewSellerVerificationRequest $request): JsonResponse
    {
        $result = $this->verifications->reject(
            $sellerVerification,
            $request->user()->id,
            $request->validated('admin_note'),
        );

        return response()->json([
            'success' => true,
            'message' => 'Seller verification rejected.',
            'data' => new SellerVerificationResource($result),
        ], 200);
    }
}
