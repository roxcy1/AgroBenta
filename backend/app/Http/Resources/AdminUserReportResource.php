<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class AdminUserReportResource extends JsonResource
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
            'description' => $this->description,
            'status' => $this->status?->value,
            'status_label' => $this->status?->label(),
            'reporter' => $this->reporter === null ? null : [
                'id' => $this->reporter->id,
                'name' => $this->reporter->name,
            ],
            'reported_user' => $this->reportedUser === null ? null : [
                'id' => $this->reportedUser->id,
                'name' => $this->reportedUser->name,
                'status' => $this->reportedUser->trashed() ? 'deactivated' : 'active',
                'pending_transactions_count' => (int) ($this->reportedUser->pending_buyer_transactions_count ?? 0)
                    + (int) ($this->reportedUser->pending_seller_transactions_count ?? 0),
            ],
            'has_evidence' => $this->evidence_path !== null && $this->evidence_path !== '',
            'reviewer' => $this->reviewer === null ? null : [
                'id' => $this->reviewer->id,
                'name' => $this->reviewer->name,
            ],
            'reviewed_at' => $this->reviewed_at?->toISOString(),
            'admin_note' => $this->admin_note,
            'created_at' => $this->created_at?->toISOString(),
        ];
    }
}
