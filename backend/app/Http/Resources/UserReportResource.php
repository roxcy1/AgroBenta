<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Reporter-safe projection of a newly created report.
 *
 * Deliberately omits reporter identity, moderation fields, and the evidence
 * path. The reporter never receives another account's private data.
 */
class UserReportResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'reason' => $this->reason?->value,
            'reason_label' => $this->reason?->label(),
            'status' => $this->status?->value,
            'status_label' => $this->status?->label(),
            'created_at' => $this->created_at?->toISOString(),
        ];
    }
}
