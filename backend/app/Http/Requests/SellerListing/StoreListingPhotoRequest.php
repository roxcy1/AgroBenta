<?php

namespace App\Http\Requests\SellerListing;

use App\Models\Listing;
use Illuminate\Foundation\Http\FormRequest;

/**
 * Body for uploading photos to a listing the caller owns.
 *
 * Ownership is *not* decided here. The route sits behind `auth:sanctum`,
 * `ability:mobile` and the `seller` capability gate, and the controller
 * resolves the listing through the same ownership-scoped lookup the other
 * seller-listing actions use — a listing owned by another seller is a 404
 * there, before any listing-dependent rule in the service could run, so no
 * status code this request can produce tells a stranger that an id exists.
 *
 * What this class owns is the file allow-list (functional documentation §4.5,
 * contract §4.5.2): explicit, closed, and enforced at the boundary. The
 * per-request ceiling here (10) matches the per-listing ceiling in the
 * service; the service adds the *cumulative* check (existing photos + these
 * files ≤ 10) because only it can see the stored count.
 */
class StoreListingPhotoRequest extends FormRequest
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
            // `Listing::PHOTO_LIMIT`, not a literal: the per-request ceiling is
            // the per-listing ceiling, and one number cannot drift from the
            // other.
            'photos' => ['required', 'array', 'min:1', 'max:'.Listing::PHOTO_LIMIT],

            // The mime allow-list is a list, not a denylist: `jpg` and `jpeg`
            // are both named because the guessed extension for `image/jpeg`
            // varies, and nothing outside jpeg/png/webp is ever stored.
            // `max:5120` is KB — 5 MB per file, as approved.
            'photos.*' => ['file', 'mimes:jpg,jpeg,png,webp', 'max:5120'],
        ];
    }
}
