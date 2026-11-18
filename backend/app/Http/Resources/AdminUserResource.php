<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class AdminUserResource extends JsonResource
{
    /**
     * Transform the resource into an array.
     *
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $pendingTransactions = (int) ($this->pending_buyer_transactions_count ?? 0)
            + (int) ($this->pending_seller_transactions_count ?? 0);

        return [
            'id' => $this->id,
            'name' => $this->name,
            'email' => $this->email,
            'role' => $this->role?->value,
            'seller_capability' => $this->seller_capability?->value,
            'email_verified_at' => $this->email_verified_at?->toISOString(),
            'status' => $this->trashed() ? 'deactivated' : 'active',
            'deactivated_at' => $this->deleted_at?->toISOString(),
            'deactivation_reason' => $this->deactivation_reason,
            'deactivated_by' => $this->deactivated_by === null ? null : [
                'id' => $this->deactivated_by,
                'name' => $this->deactivatedBy?->name,
            ],
            'reports_count' => (int) ($this->reports_count ?? 0),
            'pending_transactions_count' => $pendingTransactions,
            'created_at' => $this->created_at?->toISOString(),
            'updated_at' => $this->updated_at?->toISOString(),
        ];
    }
}
