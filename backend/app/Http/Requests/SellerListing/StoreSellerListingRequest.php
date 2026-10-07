<?php

namespace App\Http\Requests\SellerListing;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Body for creating a listing.
 *
 * The four required fields are the minimum a listing needs to be *identifiable*,
 * which is what a draft needs to be: something the seller can name, place and
 * price, so they can come back to it. Everything else is optional and validated
 * only if sent.
 *
 * The contract does not permit a wholly incomplete draft, and this request does
 * not invent one. Validation here is a contract- and storage-shaped decision,
 * not a workflow one: relaxing it to allow a seller to save an empty listing
 * would mean inventing a rule the documentation does not have, and the
 * browser-based Admin Web flow is where partial entry belongs.
 */
class StoreSellerListingRequest extends FormRequest
{
    use SellerListingRules;

    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, list<string>>
     */
    public function rules(): array
    {
        // `required` is added last so it takes precedence over the optional
        // definition of the same field; applied the other way, `livestock_type`
        // would silently revert to optional and a listing could be created with no
        // livestock type at all.
        return $this->mergeRules(
            $this->submissionRules(),
            $this->ownershipRules(),
            array_map(
                static fn (array $rules): array => ['required', ...$rules],
                $this->requiredFieldRules(),
            ),
        );
    }
}
