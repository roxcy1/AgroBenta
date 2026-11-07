<?php

namespace App\Data;

/**
 * Canonical units for the prediction contract: months and kilograms.
 */
final readonly class PriceSuggestionInput
{
    public function __construct(
        public string $livestockType,
        public string $breed,
        public string $sex,
        public float $ageMonths,
        public float $weightKg,
    ) {
        //
    }

    /**
     * @return array{livestock_type: string, breed: string, sex: string, age_months: float, weight_kg: float}
     */
    public function toArray(): array
    {
        return [
            'livestock_type' => $this->livestockType,
            'breed' => $this->breed,
            'sex' => $this->sex,
            'age_months' => $this->ageMonths,
            'weight_kg' => $this->weightKg,
        ];
    }
}
