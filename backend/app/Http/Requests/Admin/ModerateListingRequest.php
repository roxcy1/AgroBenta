<?php

namespace App\Http\Requests\Admin;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Body for the two listing moderation actions that carry no input: approve and
 * deactivate.
 *
 * Deliberately empty, for the same reason `SellerListingActionRequest` is: the
 * path carries the listing, and the `admin` group middleware has already proved
 * who is asking. A dedicated request class rather than reusing
 * `ListListingsRequest` keeps the read filter rules and the write rules
 * genuinely separate, so a moderation endpoint can never acquire `status` by
 * inheritance.
 *
 * Notably absent is any way to name a target status. The state each action
 * produces is fixed by the documented lifecycle [D-02] and lives in
 * `AdminListingService`; nothing a client sends can move a listing somewhere the
 * contract has not already put it, which is what makes these endpoints the only
 * publication path there is. `status` is `prohibited` rather than merely
 * ignored, so a client that posts `status=active` to `/approve` is told it sent
 * something illegal instead of quietly getting the transition the endpoint
 * always performs — the same treatment `SellerListingRules::ownershipRules()`
 * gives the seller surface.
 *
 * Rejection is the one action that carries a note, so it has its own request in
 * `RejectListingRequest` rather than an optional field here that two of the three
 * endpoints would ignore.
 */
class ModerateListingRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, list<string>>
     */
    public function rules(): array
    {
        return [
            'status' => ['prohibited'],
        ];
    }
}
