<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;
use App\Models\ListingInventoryReconciliation;

/**
 * The administrator-facing projection of a livestock listing.
 *
 * Admin-oriented by design, and deliberately not the mobile projection: it
 * embeds the seller's email address and carries `admin_note`, neither of which
 * belongs in a marketplace or seller response (functional documentation §10.4,
 * contract §8.1). `MobileListingResource` is a separate class rather than a
 * trimmed copy of this one, because a shared resource gets fields re-added for
 * one client and silently re-exposed to the other.
 */
class ListingResource extends JsonResource
{
    /**
     * Transform the resource into an array.
     *
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $reconciliationRequired = (bool) $this->inventory_reconciliation_required;
        $reserved = $this->resource->getAttribute('reserved_quantity');
        $completed = $this->resource->getAttribute('accounted_completed_quantity');

        return [
            'id' => $this->id,
            'seller' => [
                'id' => $this->seller->id,
                'name' => $this->seller->name,
                'email' => $this->seller->email,
            ],
            'livestock_type' => $this->livestock_type,
            'breed' => $this->breed,
            'age_value' => $this->age_value === null ? null : (int) $this->age_value,
            'age_unit' => $this->age_unit,
            'age_information' => $this->age_information,
            'gender' => $this->gender,
            'weight_value' => $this->weight_value === null ? null : (float) $this->weight_value,
            'weight_unit' => $this->weight_unit,
            'weight_information' => $this->weight_information,
            // `quantity` remains available stock for the existing Admin Web
            // contract; the richer inventory projections are additive.
            'quantity' => $this->quantity,
            'total_quantity' => $reconciliationRequired ? null : $this->total_quantity,
            'reserved_quantity' => $reconciliationRequired ? null : (int) ($reserved ?? 0),
            'platform_sold_quantity' => $reconciliationRequired ? null : (int) ($completed ?? 0),
            'sold_quantity' => $reconciliationRequired
                ? null
                : (int) ($completed ?? 0) + (int) $this->externally_sold_quantity,
            'externally_sold_quantity' => $reconciliationRequired
                ? null
                : $this->externally_sold_quantity,
            'available_quantity' => $reconciliationRequired ? null : $this->quantity,
            'inventory_reconciliation_required' => $reconciliationRequired,
            'legacy_quantity_snapshot' => $this->legacy_quantity_snapshot,
            'unaccounted_inventory_transactions' => $this->whenLoaded(
                'unaccountedInventoryTransactions',
                fn (): array => $this->unaccountedInventoryTransactions
                    ->map(fn ($transaction): array => [
                        'id' => (int) $transaction->id,
                        'status' => $transaction->status?->value,
                        'quantity' => (int) $transaction->quantity,
                    ])
                    ->values()
                    ->all(),
            ),
            'latest_inventory_reconciliation' => $this->whenLoaded(
                'inventoryReconciliations',
                function (): ?array {
                    /** @var ListingInventoryReconciliation|null $reconciliation */
                    $reconciliation = $this->inventoryReconciliations->first();

                    return $reconciliation === null ? null : [
                        'id' => $reconciliation->id,
                        'admin' => $reconciliation->admin ? [
                            'id' => $reconciliation->admin->id,
                            'name' => $reconciliation->admin->name,
                        ] : null,
                        'verified_physical_quantity' => $reconciliation->verified_physical_quantity,
                        'verified_pending_quantity' => $reconciliation->verified_pending_quantity,
                        'verified_completed_quantity' => $reconciliation->verified_completed_quantity,
                        'verified_externally_sold_quantity' => $reconciliation->verified_externally_sold_quantity,
                        'verified_total_quantity' => $reconciliation->verified_total_quantity,
                        'verified_available_quantity' => $reconciliation->verified_available_quantity,
                        'reason' => $reconciliation->reason,
                        'evidence' => $reconciliation->evidence,
                        'created_at' => $reconciliation->created_at?->toISOString(),
                    ];
                },
            ),
            'asking_price' => $this->asking_price,
            'location' => $this->location,
            'health_status' => $this->health_status,
            'vaccination' => $this->vaccination,
            'short_description' => $this->short_description,
            'additional_notes' => $this->additional_notes,
            // Absolute, fetchable URLs in stored order, so a moderator can see
            // the animal before approving it. `Listing` resolves each stored
            // filename through the `listing-photos` disk (D-10), the same source
            // `MobileListingResource` reads; no schema change is involved.
            'photos' => $this->photos,
            'status' => $this->status?->value,
            // Administrator-only: the reason a moderator gave when rejecting
            // this listing. Never present on `MobileListingResource`, so a
            // seller reading their own listing does not receive it.
            'admin_note' => $this->admin_note,
            'created_at' => $this->created_at?->toISOString(),
            'updated_at' => $this->updated_at?->toISOString(),
        ];
    }
}
