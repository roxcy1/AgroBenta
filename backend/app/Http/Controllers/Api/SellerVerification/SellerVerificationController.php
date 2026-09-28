<?php

namespace App\Http\Controllers\Api\SellerVerification;

use App\Http\Controllers\Controller;
use App\Http\Requests\SellerVerification\SubmitSellerVerificationRequest;
use App\Http\Resources\MobileSellerVerificationResource;
use App\Services\SellerVerification\SellerVerificationService;
use DomainException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

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
}
