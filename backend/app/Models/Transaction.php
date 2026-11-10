<?php

namespace App\Models;

use App\Enums\FulfillmentStatus;
use App\Enums\TransactionStatus;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable([
    'buyer_id', 'seller_id', 'listing_id', 'offer_id', 'quantity',
    'total_amount', 'pickup_date', 'payment_method', 'collection_method',
    'inventory_reserved', 'status', 'fulfillment_status', 'completed_at',
    'receipt_snapshot',
])]
class Transaction extends Model
{
    /**
     * Get the attributes that should be cast.
     *
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'status' => TransactionStatus::class,
            'fulfillment_status' => FulfillmentStatus::class,
            'quantity' => 'integer',
            'total_amount' => 'decimal:2',
            'pickup_date' => 'date',
            'inventory_reserved' => 'boolean',
            'completed_at' => 'datetime',
            'receipt_snapshot' => 'array',
        ];
    }

    /**
     * The stable display reference for this transaction.
     *
     * The id remains the canonical key; this is the same `TRX-###` shape the
     * mobile app has always shown, kept on the server so the receipt and the
     * app cannot drift.
     */
    public function receiptReference(): string
    {
        return sprintf('TRX-%03d', $this->getKey());
    }

    public function buyer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'buyer_id')->withTrashed();
    }

    public function seller(): BelongsTo
    {
        return $this->belongsTo(User::class, 'seller_id')->withTrashed();
    }

    public function listing(): BelongsTo
    {
        return $this->belongsTo(Listing::class);
    }
}
