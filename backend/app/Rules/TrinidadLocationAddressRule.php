<?php

namespace App\Rules;

use App\Support\TrinidadLocationAddress;
use Closure;
use Illuminate\Contracts\Validation\ValidationRule;

/** Enforces the approved canonical address for newly supplied locations. */
final class TrinidadLocationAddressRule implements ValidationRule
{
    public function __construct(private readonly ?string $unchangedLegacyValue = null) {}

    public function validate(string $attribute, mixed $value, Closure $fail): void
    {
        if (! is_string($value)) {
            return; // The request's `string` rule reports the type error.
        }

        $value = trim($value);
        if ($this->unchangedLegacyValue !== null &&
            $value === trim($this->unchangedLegacyValue)) {
            return;
        }

        if (TrinidadLocationAddress::parse($value) === null) {
            $fail('Choose a barangay in Trinidad, Bohol and enter a valid location.');
        }
    }
}
