<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * The seller-facing price-estimate projection.
 *
 * min/max remain null because the current provider is point-only; no range is
 * invented. Provider warnings, status and provenance are additive fields so the
 * mobile client can present the estimate honestly.
 */
class AiPriceEstimateResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $metadata = $this->provider_metadata ?? [];

        return [
            'listing_id' => $this->listing_id,
            'estimated_min' => $this->estimated_min,
            'estimated_max' => $this->estimated_max,
            'estimated_value' => $this->estimated_value,
            'basis' => $this->basis,
            'input_snapshot' => $this->input_snapshot,
            'estimated_at' => $this->estimated_at?->toISOString(),
            'status' => $this->status,
            'warnings' => $metadata['warnings'] ?? [],
            'reason_codes' => $metadata['reason_codes'] ?? [],
            'provenance' => $metadata['provenance'] ?? null,
            'model_version' => $metadata['model_version'] ?? null,
        ];
    }
}
