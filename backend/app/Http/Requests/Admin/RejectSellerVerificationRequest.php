<?php

namespace App\Http\Requests\Admin;

/**
 * Body for rejecting a seller verification.
 *
 * Unlike a listing rejection, a verification rejection is the applicant's only
 * explanation: the approved functional documentation states that `admin_note`
 * "explains why" a verification was rejected and is "shown to the user on
 * `rejected`". A rejection therefore requires a note rather than accepting an
 * empty one.
 */
class RejectSellerVerificationRequest extends ReviewSellerVerificationRequest
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
