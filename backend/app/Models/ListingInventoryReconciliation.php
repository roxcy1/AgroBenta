<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable([
    'listing_id', 'admin_id', 'verified_physical_quantity',
    'verified_pending_quantity', 'verified_completed_quantity',
    'verified_externally_sold_quantity', 'verified_total_quantity',
    'verified_available_quantity', 'accounted_transaction_ids',
    'reason', 'evidence',
])]
class ListingInventoryReconciliation extends Model
{
    protected function casts(): array
    {
        return [
            'verified_physical_quantity' => 'integer',
            'verified_pending_quantity' => 'integer',
            'verified_completed_quantity' => 'integer',
            'verified_externally_sold_quantity' => 'integer',
            'verified_total_quantity' => 'integer',
            'verified_available_quantity' => 'integer',
            'accounted_transaction_ids' => 'array',
        ];
    }

    public function listing(): BelongsTo
    {
        return $this->belongsTo(Listing::class);
    }

    public function admin(): BelongsTo
    {
        return $this->belongsTo(User::class, 'admin_id')->withTrashed();
    }
}
