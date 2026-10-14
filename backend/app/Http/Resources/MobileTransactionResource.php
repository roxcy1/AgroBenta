<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * The mobile-safe projection of a transaction.
 *
 * The administrator-facing `TransactionResource` is not reused here. It embeds
 * both `buyer.email` and `seller.email`; a mobile reader is a counterparty,
 * not an administrator, and must see only their own side plus the
 * counterparty's contact — never both emails at once (functional
 * documentation §10.4, contract §8.1).
 *
 * Which side is the counterparty is decided server-side from the token: the
 * viewer sees the other party's `{ id, name, email }` under `counterparty`.
 * The viewer's own identity is already known to the viewer.
 */
class MobileTransactionResource extends JsonResource
{
    /**
     * Transform the resource into an array.
     *
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $viewerId = (int) $request->user()?->getAuthIdentifier();
        $isBuyer = (int) $this->buyer_id === $viewerId;
        $counterparty = $isBuyer ? $this->seller : $this->buyer;

        return [
            'id' => $this->id,
            'role' => $isBuyer ? 'buyer' : 'seller',
            'listing' => [
                'id' => $this->listing->id,
                'livestock_type' => $this->listing->livestock_type,
                'breed' => $this->listing->breed,
                'photos' => $this->listing->photos,
            ],
            'counterparty' => [
                'id' => $counterparty->id,
                'name' => $counterparty->name,
                'email' => $counterparty->email,
            ],
            'quantity' => $this->quantity,
            'total_amount' => $this->total_amount,
            'status' => $this->status?->value,
            'created_at' => $this->created_at?->toISOString(),
            'updated_at' => $this->updated_at?->toISOString(),
        ];
    }
}
