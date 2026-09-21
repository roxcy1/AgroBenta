<?php

namespace App\Models;

use App\Enums\ListingStatus;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable([
    'seller_id', 'livestock_type', 'breed', 'age_value', 'age_unit',
    'gender', 'weight_value', 'weight_unit', 'quantity', 'asking_price',
    'location', 'health_status', 'vaccination', 'short_description',
    'additional_notes', 'photos', 'status',
])]
class Listing extends Model
{
    /**
     * Get the attributes that should be cast.
     *
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'status' => ListingStatus::class,
            'photos' => 'array',
            'quantity' => 'integer',
            'asking_price' => 'decimal:2',
        ];
    }

    public function seller(): BelongsTo
    {
        return $this->belongsTo(User::class, 'seller_id');
    }

    public function aiPriceEstimates(): HasMany
    {
        return $this->hasMany(AiPriceEstimate::class);
    }

    public function transactions(): HasMany
    {
        return $this->hasMany(Transaction::class);
    }
}
