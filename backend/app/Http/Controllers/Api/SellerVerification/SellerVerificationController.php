<?php

namespace App\Http\Controllers\Api\SellerVerification;

use App\Enums\SellerCapability;
use App\Enums\SellerVerificationDocumentType;
use App\Http\Controllers\Controller;
use App\Http\Requests\SellerVerification\SubmitSellerVerificationRequest;
use App\Http\Requests\SellerVerification\UploadSellerVerificationDocumentRequest;
use App\Http\Resources\MobileSellerVerificationResource;
use App\Services\SellerVerification\SellerVerificationDocumentService;
use App\Services\SellerVerification\SellerVerificationService;
use DomainException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Mobile seller verification: submission and the caller's own status.
 *
 * Not the administrator review surface. `Api\Admin\SellerVerificationController`
 * lists every verification for review and acts on any record it is handed; a
 * mobile token cannot reach it (`ability:admin`), and nothing here is shared
 * with it. This controller creates nothing but the caller's own verification,
 * reads nothing but the caller's own verification, and never changes
 * `seller_capability`.
 *
 * Both responses use `MobileSellerVerificationResource`, which is not the admin
 * resource trimmed down: a review record embeds `seller.email` and a
 * `reviewer` object, and handing an administrator's identity to a phone is
 * precisely what contract §8.1 forbids.
 */
class SellerVerificationController extends Controller
{
    public function __construct(
        private readonly SellerVerificationService $verifications,
        private readonly SellerVerificationDocumentService $documents,
    ) {
        //
    }

    /**
     * Submit a seller verification.
     *
     * Creates a new record and never updates an existing one, so a rejected
     * verification is preserved as history when the user resubmits (functional
     * documentation §3.2). Submission alone grants no capability: the response
     * carries `status: submitted` and the account is still a buyer.
     */
    public function store(SubmitSellerVerificationRequest $request): JsonResponse
    {
        try {
            $verification = $this->verifications->submit(
                $request->user(),
                $request->safe()->only([
                    'business_name',
                    'business_location',
                    'business_description',
                    'id_document_ref',
                ]),
            );
        } catch (DomainException $exception) {
            if ($exception->getMessage() === SellerVerificationService::OPEN_EXISTS) {
                return response()->json([
                    'success' => false,
                    'message' => 'A seller verification is already in review. '
                        .'Wait for a decision before submitting another.',
                ], 409);
            }

            if ($exception->getMessage() === SellerVerificationService::DOCUMENTS_MISSING) {
                return $this->missingDocumentsResponse(
                    $this->documents->missingStaged($request->user()),
                );
            }

            throw $exception;
        }

        return response()->json([
            'success' => true,
            'message' => 'Seller verification submitted.',
            'data' => new MobileSellerVerificationResource($verification),
        ], 201);
    }

    /**
     * The caller's current verification, or `404` if they have never submitted.
     *
     * A single record, resolved server-side. A caller who has never submitted is
     * a `404` rather than an empty object so the client can tell "no
     * verification yet" from "a verification with nothing in it" without
     * inspecting nullable fields.
     */
    public function me(Request $request): JsonResponse
    {
        $verification = $this->verifications->currentFor($request->user());

        if ($verification === null) {
            abort(404, 'No seller verification has been submitted.');
        }

        return response()->json([
            'success' => true,
            'data' => new MobileSellerVerificationResource($verification),
        ], 200);
    }

    /**
     * `POST /api/seller-verification/documents` — stage one required document.
     *
     * The response deliberately carries no path and no URL. The file is on a
     * private disk, and the only way to read it back is the authenticated
     * endpoint below.
     */
    public function storeDocument(
        UploadSellerVerificationDocumentRequest $request,
    ): JsonResponse {
        $user = $request->user();

        if ($user->seller_capability === SellerCapability::Seller) {
            return response()->json([
                'success' => false,
                'message' => 'This account is already an approved seller.',
            ], 403);
        }

        if ($this->verifications->currentFor($user)?->isOpen()) {
            return response()->json([
                'success' => false,
                'message' => 'A seller verification is already in review. '
                    .'Wait for a decision before uploading documents.',
            ], 409);
        }

        $type = $request->documentType();
        $this->documents->stage($user, $type, $request->file('document'));

        return response()->json([
            'success' => true,
            'message' => 'Document uploaded.',
            'data' => [
                'type' => $type->value,
                'uploaded' => true,
            ],
        ], 201);
    }

    /**
     * `DELETE /api/seller-verification/documents/{type}` — remove a staged
     * document before submission.
     *
     * Only the staging area is mutable. Once an application has been submitted
     * its documents are part of the record an administrator reviews, and this
     * route does not reach them.
     */
    public function destroyDocument(Request $request, string $type): JsonResponse
    {
        $documentType = $this->documentTypeOrAbort($type);

        if (! $this->documents->forgetStaged($request->user(), $documentType)) {
            abort(404, 'No staged document of that type exists.');
        }

        return response()->json([
            'success' => true,
            'message' => 'Document removed.',
        ], 200);
    }

    /**
     * `GET /api/seller-verification/documents/{type}` — stream one document the
     * caller submitted.
     *
     * Owner-only by construction: the record is resolved from the token, never
     * from a route parameter. No other account can name this caller's record,
     * and an administrator uses the separate admin route.
     */
    public function showDocument(Request $request, string $type): StreamedResponse
    {
        $documentType = $this->documentTypeOrAbort($type);
        $verification = $this->verifications->currentFor($request->user());

        abort_if($verification === null, 404);

        return $this->documents->response($verification, $documentType);
    }

    /**
     * A `422` naming the document fields the submission is missing.
     *
     * The keys match the mobile form's two document cards (`id_document` and
     * `selfie`), so the existing per-field error rendering applies without a
     * second error shape.
     *
     * @param  list<SellerVerificationDocumentType>  $missing
     */
    private function missingDocumentsResponse(array $missing): JsonResponse
    {
        $errors = [];

        foreach ($missing as $type) {
            $errors[$type->value] = [
                $type === SellerVerificationDocumentType::IdDocument
                    ? 'Upload a clear photo of your government-issued ID.'
                    : 'Upload a selfie holding the same ID.',
            ];
        }

        return response()->json([
            'success' => false,
            'message' => 'Upload both required documents before submitting.',
            'errors' => $errors,
        ], 422);
    }

    private function documentTypeOrAbort(
        string $type,
    ): SellerVerificationDocumentType {
        $documentType = SellerVerificationDocumentType::tryFrom($type);

        abort_if($documentType === null, 404, 'Unknown document type.');

        return $documentType;
    }
}
