<?php

namespace App\Http\Requests\Marketplace;

use App\Enums\LivestockType;
use Closure;
use Illuminate\Foundation\Http\FormRequest;

/**
 * Query parameters for the buyer marketplace.
 *
 * An allow-list, not a denylist: only the filters named in the mobile API
 * contract §5.2 are accepted, and the controller may only pass the keys
 * declared here to the service. A parameter that is not listed therefore has no
 * path into the query at all, which is what keeps a new request field from
 * becoming a marketplace filter by accident.
 */
class IndexListingRequest extends FormRequest
{
    public function authorize(): bool
    {
        // Authorization is the route's job: `auth:sanctum` plus the
        // `ability:mobile` guard, which is what makes this a marketplace
        // request rather than an admin one.
        return true;
    }

    /**
     * Normalise the two multi-select filters to lists.
     *
     * A scalar is wrapped rather than rejected, so a client written before
     * multi-select existed keeps working unchanged. Entries that are `null` or
     * an empty string are dropped: an empty filter is the same as no filter,
     * and letting it reach the query would turn "no selection" into a
     * `whereIn` for the empty string.
     */
    protected function prepareForValidation(): void
    {
        foreach (['livestock_type', 'breed'] as $key) {
            $value = $this->input($key);

            if ($value === null) {
                continue;
            }

            $values = is_array($value) ? $value : [$value];

            $this->merge([
                $key => array_values(array_filter(
                    $values,
                    static fn (mixed $item): bool => $item !== null && $item !== '',
                )),
            ]);
        }
    }

    /**
     * @return array<string, list<mixed>>
     */
    public function rules(): array
    {
        return [
            'search' => ['nullable', 'string', 'max:255'],

            // Multi-select. The `array` rule is always satisfied because
            // [prepareForValidation] has already wrapped a scalar; the closure
            // is what enforces the per-entry type and length. It reports on the
            // base key rather than `livestock_type.*` so a client that sends an
            // oversized scalar sees the same error key it always has.
            //
            // The `max` caps the number of selected values at the size of the
            // server-owned catalog, so the bound cannot drift from the enum:
            // a client cannot widen the request past what the UI can offer.
            'livestock_type' => [
                'nullable',
                'array',
                'max:'.count(LivestockType::cases()),
                $this->stringListRule(),
            ],
            'breed' => [
                'nullable',
                'array',
                'max:'.array_sum(array_map(
                    static fn (LivestockType $type): int => count($type->breeds()),
                    LivestockType::cases(),
                )),
                $this->stringListRule(),
            ],

            'gender' => ['nullable', 'string', 'in:male,female'],

            // Ages are sent in months, regardless of the unit a seller stored
            // them in; the repository converts before comparing. The ceiling is
            // the documented 300-month maximum [DEC-01].
            'min_age' => ['nullable', 'numeric', 'min:0', 'max:300'],
            'max_age' => ['nullable', 'numeric', 'min:0', 'max:300'],

            // Weights are sent in kilograms. The ceiling is the
            // `decimal(10,2)` column maximum.
            'min_weight' => ['nullable', 'numeric', 'min:0', 'max:99999999.99'],
            'max_weight' => ['nullable', 'numeric', 'min:0', 'max:99999999.99'],

            'location' => ['nullable', 'string', 'max:255'],
            'min_price' => ['nullable', 'numeric', 'min:0'],
            'max_price' => ['nullable', 'numeric', 'min:0'],
            'page' => ['nullable', 'integer', 'min:1'],
            'per_page' => ['nullable', 'integer', 'between:1,50'],

            // Marketplace visibility is the server's decision [D-02 rule 9], and
            // a `status` parameter is rejected rather than honoured — accepting
            // it would be the rule violated, and dropping it silently would
            // hide a client bug. `active` is not a permitted value either: the
            // endpoint is active-only by construction, not by parameter.
            'status' => ['prohibited'],

            // Ownership is never a client-selected scope on a read endpoint
            // (functional documentation §10.3). There is no "browse one
            // seller's listings" marketplace view, and this phase is read-only,
            // so the field is refused rather than quietly ignored.
            'seller_id' => ['prohibited'],
        ];
    }

    /**
     * A rule that every entry of a normalised list is a string of at most 255
     * characters.
     */
    private function stringListRule(): Closure
    {
        return function (string $attribute, mixed $value, Closure $fail): void {
            foreach ($value as $item) {
                if (! is_string($item) || mb_strlen($item) > 255) {
                    $fail("The {$attribute} field must contain only strings of at most 255 characters.");

                    return;
                }
            }
        };
    }
}
