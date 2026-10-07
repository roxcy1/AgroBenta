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
 * `rules()` is empty because the path already carries everything: the listing id,
 * and the seller identity in the token. There is nothing to validate and nothing
 * to forbid.
 */
class SellerListingActionRequest extends FormRequest
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
        return [];
    }
}
