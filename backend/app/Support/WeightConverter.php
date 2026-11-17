<?php

namespace App\Support;

use InvalidArgumentException;

/**
 * Canonical weight conversion for the price-suggestion boundary.
 *
 * Listings keep the seller's entered value and unit. The ML service accepts
 * kilograms only, so every canonical-weight consumer must use this helper
 * rather than re-implementing the factor.
 */
final class WeightConverter
{
    public const KILOGRAMS_PER_POUND = 0.45359237;

    public static function toKilograms(float|int|string $value, string $unit): float
    {
        return match ($unit) {
            'kg' => (float) $value,
            'lb' => (float) $value * self::KILOGRAMS_PER_POUND,
            default => throw new InvalidArgumentException(
                "Unsupported weight unit: {$unit}.",
            ),
        };
    }
}
