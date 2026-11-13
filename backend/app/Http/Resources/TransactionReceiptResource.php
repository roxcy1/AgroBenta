<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * The buyer/seller-safe projection of a completed receipt.
 *
 * It deliberately contains no email addresses, phone numbers, photos or
 * location. The snapshot is authoritative when present; a legacy completed row
 * (predating the snapshot) falls back to the live relations and `updated_at`,
 * which is the only completion marker those rows have.
 *
 * `payment_method` is a recorded preference, never proof of payment.
 */
class TransactionReceiptResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $snapshot = $this->receipt_snapshot;

        if (is_array($snapshot) && $snapshot !== []) {
            return $snapshot;
        }

        $completedAt = $this->completed_at ?? $this->updated_at;

        return [
            'version' => 1,
            'reference' => $this->receiptReference(),
            'completed_at' => $completedAt?->toISOString(),
            'buyer' => [
                'name' => (string) $this->buyer?->name,
            ],
            'seller' => [
                'name' => (string) $this->seller?->name,
            ],
            'listing' => [
                'livestock_type' => (string) $this->listing?->livestock_type,
                'breed' => (string) ($this->listing?->breed ?? ''),
            ],
            'quantity' => (int) $this->quantity,
            'total_amount' => (string) $this->total_amount,
            'payment_method' => $this->payment_method,
            'collection_method' => $this->collection_method,
            'status' => $this->status?->value,
        ];
    }
}
