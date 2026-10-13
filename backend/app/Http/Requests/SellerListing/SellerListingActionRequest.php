<?php

namespace App\Http\Requests\SellerListing;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Body for the two actions that take no input: submit and destroy.
 *
 * A dedicated class rather than reusing `UpdateSellerListingRequest`, so that
 * `PATCH /seller/listings/{id}` and `POST /seller/listings/{id}/submit` cannot
 * accidentally acquire each other's rules. A submit carrying a body is almost
 * certainly a client that meant to send an edit, and keeping the two endpoints'
 * rule sets genuinely different is worth a small extra class.
 *
 * The contract's allow-list for these two routes is empty: §5.4 records
 * "Request fields: None" for both, and the §6.2 security matrix gives `submit`
 * "Fields the client may set: none — fields rejected if present: all". Laravel
 * ignores a key that appears in no rule, so a literally empty `rules()` would
 * *silently drop* every field instead of rejecting it — and a silently dropped
 * `status` or `seller_id` is exactly the defect [SEC] §4.5 exists to prevent
 * (F-11: "silently dropping hides a client bug; accepting it is a security
 * defect"). The empty allow-list is therefore enforced explicitly below.
 *
 * An absent body, or an empty `{}`, yields no rules and passes — which is what
 * the mobile client sends, because neither action reads any input.
 */
class SellerListingActionRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * An empty allow-list: no field may be present on either action.
     *
     * Built from the keys actually sent rather than from a written list of
     * forbidden names, because a written list is a denylist and a denylist fails
     * open the moment a field is added to the model later (functional
     * documentation §10.1, contract §4.5.2). Every present key is `prohibited`,
     * so a future column is rejected the day it appears instead of quietly
     * accepted, and the client gets the standard `422` envelope keyed to the
     * field it should not have sent. Query-string parameters are included, so
     * `?status=active` on `submit` is refused too — the contract deliberately
     * specifies no `?status=` variant of the action.
     *
     * @return array<string, list<string>>
     */
    public function rules(): array
    {
        return array_fill_keys(
            array_keys($this->all()),
            ['prohibited'],
        );
    }
}
