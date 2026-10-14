<?php

namespace App\Http\Requests\SellerListing;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Body for removing one photo from a listing the caller owns.
 *
 * The photo is named by the value the client was served: the bare filename or
 * the full URL both work, because the service collapses either to a filename
 * before matching — a client holds URLs, and forcing it to parse its own URL
 * would be an avoidable trap.
 *
 * As with the upload request, ownership is the controller's job (404 via the
 * ownership-scoped lookup), not this class's: nothing here reads the listing,
 * so nothing here can leak whether an id exists.
 */
class DeleteListingPhotoRequest extends FormRequest
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
        // Accepted from the query string or a JSON body — `DELETE` bodies are
        // awkward for some HTTP clients, so `?photo=` is the natural transport
        // and `$request->validated()` reads it from either place.
        //
        // `max:2048`, not `max:255`: the value may be a full URL on a long
        // domain (same bound as `avatar_url`), and it is collapsed to a
        // filename before use.
        return [
            'photo' => ['required', 'string', 'max:2048'],
        ];
    }
}
