<?php

namespace App\Models;

use App\Enums\InquiryCollectionMethod;
use App\Enums\InquiryContactMethod;
use App\Enums\InquiryPaymentMethod;
use App\Enums\InquiryStatus;
use App\Enums\InquiryTransactionMethod;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable([
    'buyer_id', 'seller_id', 'listing_id', 'subject', 'message',
    'purchase_interest', 'transaction_method', 'delivery_method',
    'delivery_fee', 'contact_method', 'preferred_schedule',
    'payment_method', 'collection_method', 'collection_date_option',
    'status',
])]
class Inquiry extends Model
{
    /**
     * Get the attributes that should be cast.
     *
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'purchase_interest' => 'boolean',
            'transaction_method' => InquiryTransactionMethod::class,
            'contact_method' => InquiryContactMethod::class,
            'delivery_fee' => 'decimal:2',
            'preferred_schedule' => 'date',
            'payment_method' => InquiryPaymentMethod::class,
            'collection_method' => InquiryCollectionMethod::class,
            'status' => InquiryStatus::class,
        ];
    }

    public function buyer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'buyer_id');
    }

    public function seller(): BelongsTo
    {
        return $this->belongsTo(User::class, 'seller_id');
    }

    public function listing(): BelongsTo
    {
        return $this->belongsTo(Listing::class);
    }
}
