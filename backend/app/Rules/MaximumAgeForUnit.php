<?php

namespace App\Rules;

use Closure;
use Illuminate\Contracts\Validation\DataAwareRule;
use Illuminate\Contracts\Validation\ValidationRule;

/**
 * The age ceiling for the unit the seller selected [DEC-01].
 *
 * The limit is expressed in the selected unit and is not a conversion: 300
 * months is valid while 301 is not, and no value is converted to days first.
 * This is a data-aware rule rather than a conditional rule array because the
 * limit depends on a sibling field (`age_unit`) that is only known once the
 * whole payload — or, on submit, the stored row — is under validation.
 *
 * The functional documentation's §4.7 limits are approved project-owner
 * decisions, not manuscript rules.
 */
class MaximumAgeForUnit implements DataAwareRule, ValidationRule
{
    /**
     * The approved ceiling per unit: 25 years / 300 months / 9,125 days.
     *
     * @var array<string, int>
     */
    private const MAXIMUMS = [
        'day' => 9125,
        'month' => 300,
        'year' => 25,
    ];

    /**
     * The data under validation, supplied by the validator.
     *
     * @var array<string, mixed>
     */
    private array $data = [];

    /**
     * @param  array<string, mixed>  $data
     */
    public function setData(array $data): static
    {
        $this->data = $data;

        return $this;
    }

    public function validate(string $attribute, mixed $value, Closure $fail): void
    {
        $unit = $this->data['age_unit'] ?? null;

        // An unknown or absent unit belongs to the `in:` and `required_with`
        // rules, and a non-numeric age belongs to `integer`. Reporting either
        // here as well would attach a second, misleading message to the field.
        if (! is_string($unit) || ! isset(self::MAXIMUMS[$unit]) || ! is_numeric($value)) {
            return;
        }

        $maximum = self::MAXIMUMS[$unit];

        if ((float) $value > $maximum) {
            $fail("The age value must not be greater than {$maximum} {$unit}s.");
        }
    }
}
