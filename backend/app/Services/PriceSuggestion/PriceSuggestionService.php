<?php

namespace App\Services\PriceSuggestion;

use App\Contracts\PriceSuggestionProvider;
use App\Data\PriceSuggestionInput;
use App\Enums\ListingStatus;
use App\Enums\LivestockType;
use App\Exceptions\PriceSuggestionRejected;
use App\Models\AiPriceEstimate;
use App\Models\Listing;
use App\Repositories\PriceSuggestion\AiPriceEstimateRepository;
use App\Support\PriceSuggestion\BreedNormalizer;
use Illuminate\Support\Str;

/**
 * Owns the seller-facing price-estimate workflow:
 * validate the persisted listing, convert units, call the provider, and persist
 * successful estimates. It never writes asking_price or listing status.
 */
class PriceSuggestionService
{
    private const AGE_UNITS = ['day', 'month', 'year'];

    private const WEIGHT_UNITS = ['kg', 'lb'];

    public function __construct(
        private readonly PriceSuggestionProvider $provider,
        private readonly AiPriceEstimateRepository $estimates,
    ) {
        //
    }

    public function generate(Listing $listing): AiPriceEstimate
    {
        if ($listing->status !== ListingStatus::Draft) {
            throw new PriceSuggestionRejected(
                'invalid',
                ['listing_not_draft'],
                ['A price suggestion can only be requested for a draft listing.'],
                'A price suggestion can only be requested for a draft listing.',
            );
        }

        [$input, $snapshot] = $this->inputFromListing($listing);
        $result = $this->provider->predict($input);

        if (! in_array($result->status, ['ok', 'warning'], true) || $result->value <= 0) {
            throw new PriceSuggestionRejected(
                'withheld',
                ['invalid_provider_result'],
                ['The provider did not return a usable point estimate.'],
            );
        }

        $basis = Str::limit(
            sprintf(
                'Prototype CatBoost estimate from %s (%s data); reference only.',
                $result->modelVersion,
                $result->provenance,
            ),
            240,
        );

        return $this->estimates->createForListing($listing, [
            'input_snapshot' => $snapshot,
            'estimated_min' => null,
            'estimated_max' => null,
            'estimated_value' => round($result->value, 2),
            'basis' => $basis,
            'status' => $result->status,
            'provider_metadata' => [
                'provider' => 'fastapi',
                'contract_version' => $result->contractVersion,
                'model_version' => $result->modelVersion,
                'model_sha256' => $result->modelSha256,
                'provenance' => $result->provenance,
                'warnings' => $result->warnings,
                'reason_codes' => $result->reasonCodes,
            ],
            'estimated_at' => now(),
        ]);
    }

    /**
     * @return array{0: PriceSuggestionInput, 1: array<string, mixed>}
     */
    private function inputFromListing(Listing $listing): array
    {
        $livestockType = strtolower(trim((string) $listing->livestock_type));
        if (LivestockType::tryFrom($livestockType) === null) {
            throw new PriceSuggestionRejected(
                'invalid',
                ['unsupported_livestock_type'],
                ['This livestock type is not supported by the price suggestion service.'],
            );
        }

        $breed = BreedNormalizer::normalize($listing->breed, $livestockType);
        if ($breed === null) {
            throw new PriceSuggestionRejected(
                'invalid',
                ['unsupported_breed'],
                ['This breed is not supported by the price suggestion service.'],
            );
        }

        $sex = $listing->gender;
        if (! in_array($sex, ['male', 'female'], true)) {
            throw new PriceSuggestionRejected(
                'invalid',
                ['missing_sex'],
                ['Add the animal sex before requesting a price suggestion.'],
            );
        }

        $ageValue = $listing->age_value;
        $ageUnit = $listing->age_unit;
        if ($ageValue === null || $ageUnit === null || (float) $ageValue <= 0) {
            throw new PriceSuggestionRejected(
                'invalid',
                ['missing_age'],
                ['Add the animal age before requesting a price suggestion.'],
            );
        }
        if (! in_array($ageUnit, self::AGE_UNITS, true)) {
            throw new PriceSuggestionRejected(
                'invalid',
                ['invalid_age_unit'],
                ['The listing has an unsupported age unit.'],
            );
        }

        $weightValue = $listing->weight_value;
        $weightUnit = $listing->weight_unit;
        if ($weightValue === null || $weightUnit === null || (float) $weightValue <= 0) {
            throw new PriceSuggestionRejected(
                'invalid',
                ['missing_weight'],
                ['Add the animal weight before requesting a price suggestion.'],
            );
        }
        if (! in_array($weightUnit, self::WEIGHT_UNITS, true)) {
            throw new PriceSuggestionRejected(
                'invalid',
                ['invalid_weight_unit'],
                ['The listing has an unsupported weight unit.'],
            );
        }

        $ageMonths = match ($ageUnit) {
            'day' => (float) $ageValue / 30.4375,
            'year' => (float) $ageValue * 12,
            default => (float) $ageValue,
        };
        $weightKg = $weightUnit === 'lb'
            ? (float) $weightValue * 0.45359237
            : (float) $weightValue;

        if ($ageMonths <= 0 || $weightKg <= 0) {
            throw new PriceSuggestionRejected(
                'invalid',
                ['invalid_measurement'],
                ['The listing age and weight must be positive.'],
            );
        }

        $input = new PriceSuggestionInput(
            livestockType: $livestockType,
            breed: $breed,
            sex: $sex,
            ageMonths: round($ageMonths, 6),
            weightKg: round($weightKg, 4),
        );

        return [
            $input,
            [
                'livestock_type' => $livestockType,
                'breed' => $breed,
                'sex' => $sex,
                'age_months' => $input->ageMonths,
                'weight_kg' => $input->weightKg,
                'source' => [
                    'breed_raw' => $listing->breed,
                    'age_value' => $listing->age_value,
                    'age_unit' => $ageUnit,
                    'age_information' => $listing->age_information,
                    'weight_value' => $listing->weight_value,
                    'weight_unit' => $weightUnit,
                    'weight_information' => $listing->weight_information,
                ],
            ],
        ];
    }
}
