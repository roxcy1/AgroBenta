<?php

namespace App\Http\Requests\Admin;

/**
 * Body for revoking an approved seller verification.
 *
 * A revocation removes seller capability and withdraws the seller's live and
 * pending listings, so the administrator must record why. The note is retained
 * on the verification record and shown to the applicant, matching a rejection.
 */
class RevokeSellerVerificationRequest extends ReviewSellerVerificationRequest
{
    /**
     * @return array<string, list<string>>
     */
    public function rules(): array
    {
        return [
            ...parent::rules(),
            'admin_note' => ['required', 'string', 'max:1000'],
        ];
    }
}
