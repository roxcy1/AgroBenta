<?php

namespace App\Models;

use App\Enums\InquiryCollectionMethod;
use App\Enums\InquiryPaymentMethod;
use App\Enums\OfferStatus;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable([
    'inquiry_id', 'listing_id', 'seller_id', 'buyer_id',
    'proposed_amount', 'proposed_quantity', 'proposed_pickup_date', 'payment_method',
    'collection_method', 'note', 'status', 'responded_at',
])]
class Offer extends Model
{
    /**
     * Get the attributes that should be cast.
     *
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'proposed_amount' => 'decimal:2',
            'proposed_quantity' => 'integer',
            'proposed_pickup_date' => 'date',
            'payment_method' => InquiryPaymentMethod::class,
            'collection_method' => InquiryCollectionMethod::class,
            'status' => OfferStatus::class,
            'responded_at' => 'datetime',
        ];
    }

    public function inquiry(): BelongsTo
    {
        return $this->belongsTo(Inquiry::class);
    }

    public function listing(): BelongsTo
    {
        return $this->belongsTo(Listing::class);
    }

    public function seller(): BelongsTo
    {
        return $this->belongsTo(User::class, 'seller_id')->withTrashed();
    }

    public function buyer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'buyer_id')->withTrashed();
    }

    /**
     * Whether the offer is still actionable (accept / decline / withdraw).
     */
    public function isPending(): bool
    {
        return $this->status === OfferStatus::Pending;
    }
}
