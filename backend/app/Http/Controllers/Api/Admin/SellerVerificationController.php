<?php

namespace App\Http\Controllers\Api\Admin;

use App\Enums\SellerVerificationDocumentType;
use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\ListSellerVerificationsRequest;
use App\Http\Requests\Admin\RejectSellerVerificationRequest;
use App\Http\Requests\Admin\ReviewSellerVerificationRequest;
use App\Http\Resources\SellerVerificationResource;
use App\Models\SellerVerification;
use App\Services\Admin\AdminSellerVerificationService;
use App\Services\SellerVerification\SellerVerificationDocumentService;
use Illuminate\Http\JsonResponse;
use Symfony\Component\HttpFoundation\StreamedResponse;

class SellerVerificationController extends Controller
{
    public function __construct(
        private readonly AdminSellerVerificationService $verifications,
        private readonly SellerVerificationDocumentService $documents,
    ) {
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
     * Show a single seller verification request, with the applicant's prior
     * submissions so the full review history is visible.
     */
    public function show(SellerVerification $sellerVerification): JsonResponse
    {
        $sellerVerification->load(['seller:id,name,email', 'reviewer:id,name']);

        return response()->json([
            'success' => true,
            'data' => new SellerVerificationResource($sellerVerification),
            'history' => SellerVerificationResource::collection(
                $this->verifications->historyFor($sellerVerification),
            ),
        ], 200);
    }

    /**
     * Stream one submitted document for review (government ID or selfie).
     *
     * Administrator-only: this route lives inside the `admin` group, and the
     * file itself is on private storage the web server cannot address. The
     * response is streamed with `Cache-Control: private, no-store` so a shared
     * cache or proxy never retains a government ID. A document that a legacy
     * record never had answers 404 rather than an empty 200.
     */
    public function document(
        SellerVerification $sellerVerification,
        string $type,
    ): StreamedResponse {
        $documentType = SellerVerificationDocumentType::tryFrom($type);

        abort_if($documentType === null, 404, 'Unknown document type.');

        return $this->documents->response($sellerVerification, $documentType);
    }

    /**
     * Approve a seller verification request.
     */
    public function approve(SellerVerification $sellerVerification, ReviewSellerVerificationRequest $request): JsonResponse
    {
        $result = $this->verifications->approve(
            $sellerVerification,
            $request->user(),
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
    public function reject(SellerVerification $sellerVerification, RejectSellerVerificationRequest $request): JsonResponse
    {
        $result = $this->verifications->reject(
            $sellerVerification,
            $request->user(),
            $request->validated('admin_note'),
        );

        return response()->json([
            'success' => true,
            'message' => 'Seller verification rejected.',
            'data' => new SellerVerificationResource($result),
        ], 200);
    }
}
