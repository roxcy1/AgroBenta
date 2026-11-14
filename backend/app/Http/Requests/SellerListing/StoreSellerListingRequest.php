<?php

namespace App\Http\Requests\SellerListing;

use App\Enums\LivestockType;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Validator;

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
     * @return array<string, list<mixed>>
     */
    public function rules(): array
    {
        // The two quantity spellings are mutually exclusive and one is
        // required. All other core fields use the shared required-field rules.
        // `required` is added last so it takes precedence over the optional
        // definition of the same field.
        $required = $this->requiredFieldRules();
        unset($required['total_quantity']);

        return $this->mergeRules(
            $this->contentRules(),
            $this->pairRules(),
            $this->requiredMeasurementRules(),
            $this->ownershipRules(),
            array_map(
                static fn (array $rules): array => ['required', ...$rules],
                $required,
            ),
            [
                'quantity' => ['required_without:total_quantity', 'prohibits:total_quantity'],
                'total_quantity' => ['required_without:quantity', 'prohibits:quantity'],
            ],
        );
    }

    /** Enforce that a newly selected catalog breed belongs to the selected type. */
    public function after(): array
    {
        return [function (Validator $validator): void {
            if ($validator->errors()->has('livestock_type') ||
                $validator->errors()->has('breed')) {
                return;
            }

            $breed = trim((string) ($this->input('breed') ?? ''));
            if ($breed === '') {
                return;
            }

            $type = LivestockType::tryFrom((string) $this->input('livestock_type'));
            if ($type !== null &&
                ! $type->hasBreed($breed) &&
                ! $this->isAllowedLegacyBreed($breed, $type)) {
                $validator->errors()->add(
                    'breed',
                    'Choose a breed from the selected livestock type.',
                );
            }
        }];
    }

    /**
     * Override point for requests that may hold a historical breed.
     *
     * Listings created before the breed catalog existed may keep a free-text
     * breed name that is not in their type's list. Creation never holds one —
     * every *new* value must come from the catalog — so this defaults to
     * `false` and only [UpdateSellerListingRequest] relaxes it.
     */
    protected function isAllowedLegacyBreed(string $breed, LivestockType $type): bool
    {
        return false;
    }
}
