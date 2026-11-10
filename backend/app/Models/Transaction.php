<?php

namespace App\Models;

use App\Enums\TransactionStatus;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable([
    'buyer_id', 'seller_id', 'listing_id', 'offer_id', 'quantity',
    'total_amount', 'pickup_date', 'payment_method', 'collection_method',
    'status',
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
            'quantity' => 'integer',
            'total_amount' => 'decimal:2',
            'pickup_date' => 'date',
        ];
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
