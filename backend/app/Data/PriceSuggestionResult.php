<?php

namespace App\Data;

/**
 * A compatible provider response. The value is a point estimate only; min/max
 * ranges are deliberately not modelled because the current service does not
 * produce calibrated ranges.
 */
final readonly class PriceSuggestionResult
{
    /**
     * @param  list<string>  $warnings
     * @param  list<string>  $reasonCodes
     */
    public function __construct(
        public string $status,
        public float $value,
        public array $warnings,
        public array $reasonCodes,
        public string $modelVersion,
        public string $modelSha256,
        public string $provenance,
        public string $contractVersion,
    ) {
        //
    }

    public function isWarning(): bool
    {
        return $this->status === 'warning';
    }
}
