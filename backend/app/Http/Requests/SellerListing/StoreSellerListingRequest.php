<?php

namespace App\Http\Requests\SellerListing;

use App\Enums\LivestockType;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Validator;

/**
 * Body for creating a listing.
 *
 * A draft needs enough information to be identifiable and to feed the AI price
 * suggestion, but not the seller's final price or the barangay they have not
 * chosen yet. The asking price and location are therefore optional here and
 * required at submission, which [SellerListingRules::submissionRules()] and
 * [SellerListingService::submit()] enforce against the stored row.
 *
 * Everything else is validated only if sent. Age, weight and quantity remain
 * create requirements because they are the model inputs and the stock record;
 * the two publication fields are the only draft-optional ones.
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
        // required. The other create-required fields come from the shared
        // rules with `required` already attached; `total_quantity` is handled
        // by the pair of `required_without` rules below, and the publication
        // fields are deliberately omitted so a draft may save without them.
        $required = $this->requiredFieldRules();
        unset(
            $required['total_quantity'],
            $required['asking_price'],
            $required['location'],
        );

        return $this->mergeRules(
            $this->contentRules(),
            $this->pairRules(),
            $this->requiredMeasurementRules(),
            $this->ownershipRules(),
            $required,
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
