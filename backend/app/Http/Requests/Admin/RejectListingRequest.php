<?php

namespace App\Http\Requests\Admin;

/**
 * Body for rejecting a listing: the one moderation action that carries a note.
 *
 * The contract's §5.4b guard table annotates `reject` with "takes an
 * `admin_note`" and annotates `approve` and `deactivate` with nothing, so the
 * field lives here rather than in the shared [ModerateListingRequest] — where it
 * would be accepted and silently discarded on the other two endpoints.
 *
 * Optional, and optional for the same reason it is on
 * `ReviewSellerVerificationRequest`: the transition itself is unconditional, and
 * an administrator who has no reason to give is not made to invent one. Bounded
 * to 2000 characters to match `listings.additional_notes`, the column it now
 * shares a row with.
 */
class RejectListingRequest extends ModerateListingRequest
{
    /**
     * @return array<string, list<string>>
     */
    public function rules(): array
    {
        return [
            ...parent::rules(),
            'admin_note' => ['nullable', 'string', 'max:2000'],
        ];
    }
}
