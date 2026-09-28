<?php

namespace App\Http\Requests\SellerVerification;

use App\Enums\SellerCapability;
use Illuminate\Contracts\Validation\Validator;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Validation\ValidationException;

/**
 * A seller verification submission.
 *
 * An allow-list, not a denylist, and the rules below are the contract's §5.3
 * specification copied rather than re-derived, so a drift in one place cannot
 * quietly become a different API in the other.
 *
 * Two things are being defended here.
 *
 * The first is the resubmission rule. `user_id`, `status` and `submitted_at` are
 * all `#[Fillable]` on the model, so a request that carried them could file a
 * verification against somebody else's account, or backdate one to defeat the
 * "most recent record" ordering that the whole rejection/resubmission model
 * depends on. They are therefore listed as `prohibited` and a client that sends
 * one gets a 422 rather than a silently dropped key (contract §6.2: "a rejected
 * field returns 422 — it is not silently dropped. Silently dropping hides a
 * client bug; accepting it is a security defect").
 *
 * The second is that submitting grants nothing. Nothing in this request class,
 * and nothing in the controller it feeds, can set `seller_capability`; the only
 * path to `seller` is an administrator approving the record (functional
 * documentation §2.6). `seller_capability` is not merely absent from the
 * allow-list, it is `prohibited`, so a client that tries to set its own
 * capability is told so instead of appearing to succeed.
 */
class SubmitSellerVerificationRequest extends FormRequest
{
    public function authorize(): bool
    {
        // Authentication and the `ability:mobile` boundary are the route's job.
        // An approved seller has nothing to submit (contract D-07), which is a
        // state rule rather than a permission, so it is enforced in
        // `withValidator` below where the submission preconditions live.
        return true;
    }

    /**
     * @return array<string, array<int, string>>
     */
    public function rules(): array
    {
        return [
            'business_name' => ['required', 'string', 'max:255'],
            'business_location' => ['sometimes', 'nullable', 'string', 'max:255'],
            'business_description' => ['sometimes', 'nullable', 'string', 'max:2000'],

            // A reference, never a document. There is no upload endpoint, no
            // storage disk and no URL scheme (functional documentation §3.3), so
            // this field is a string the seller supplies — a document number, a
            // reference code, whatever their process uses. No multipart upload
            // is accepted and no `file` rule appears here on purpose: accepting
            // one would imply a storage path this phase may not create.
            'id_document_ref' => ['sometimes', 'nullable', 'string', 'max:255'],

            // Server-owned. A client that sends one is told no, not ignored.
            'user_id' => ['prohibited'],
            'status' => ['prohibited'],
            'reviewed_by' => ['prohibited'],
            'reviewed_at' => ['prohibited'],
            'submitted_at' => ['prohibited'],
            'admin_note' => ['prohibited'],

            // The hinge of the single-account model. Accepting it here would let a
            // buyer grant themselves seller capability and bypass the review
            // entirely, which is the exact bypass F-11 describes.
            'seller_capability' => ['prohibited'],
            'role' => ['prohibited'],
        ];
    }

    /**
     * Human-readable replacements for the field names Laravel would otherwise
     * report verbatim, so a mobile client that chose to surface
     * `business_name` learns what a person would call it.
     *
     * @return array<string, string>
     */
    public function attributes(): array
    {
        return [
            'business_name' => 'business name',
            'business_location' => 'business location',
            'business_description' => 'business description',
            'id_document_ref' => 'ID document reference',
        ];
    }

    /**
     * Enforce the two business preconditions that are not per-field rules.
     *
     * `after()` is used rather than `withValidator()` so that a failure is a
     * normal validation error the client's existing 422 handling already
     * understands, rather than an exception type it has never seen.
     */
    public function after(): array
    {
        return [
            function (Validator $validator): void {
                $user = $this->user();

                if ($user === null) {
                    return;
                }

                if ($user->seller_capability === SellerCapability::Seller) {
                    $validator->errors()->add(
                        'business_name',
                        'This account is already an approved seller.',
                    );
                }
            },
        ];
    }

    /**
     * Turn the "already a seller" precondition into a 403 rather than a 422.
     *
     * The contract lists `403` among this endpoint's errors and describes the
     * approved-seller case as *rejected*, not as invalid input — nothing about
     * the payload is wrong, the account is simply not eligible. A 422 would tell
     * the client to fix fields that are already correct.
     */
    protected function failedValidation(Validator $validator): void
    {
        if ($this->user()?->seller_capability === SellerCapability::Seller) {
            throw new HttpResponseException(
                response()->json([
                    'success' => false,
                    'message' => 'This account is already an approved seller.',
                ], 403),
            );
        }

        throw new ValidationException($validator);
    }
}
