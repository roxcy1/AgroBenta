<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** Administrator-only evidence and allocation record. */
class ListingInventoryReconciliationResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'listing_id' => $this->listing_id,
            'admin' => $this->admin === null ? null : [
                'id' => $this->admin->id,
                'name' => $this->admin->name,
            ],
            'verified_physical_quantity' => $this->verified_physical_quantity,
            'verified_pending_quantity' => $this->verified_pending_quantity,
            'verified_completed_quantity' => $this->verified_completed_quantity,
            'verified_externally_sold_quantity' => $this->verified_externally_sold_quantity,
            'verified_total_quantity' => $this->verified_total_quantity,
            'verified_available_quantity' => $this->verified_available_quantity,
            'accounted_transaction_ids' => $this->accounted_transaction_ids,
            'reason' => $this->reason,
            'evidence' => $this->evidence,
            'created_at' => $this->created_at?->toISOString(),
        ];
    }
}
