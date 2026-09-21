<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable([
    'listing_id', 'input_snapshot', 'estimated_min', 'estimated_max',
    'estimated_value', 'basis', 'estimated_at',
])]
class AiPriceEstimate extends Model
{
    /**
     * Get the attributes that should be cast.
     *
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'input_snapshot' => 'array',
            'estimated_at' => 'datetime',
            'estimated_min' => 'decimal:2',
            'estimated_max' => 'decimal:2',
            'estimated_value' => 'decimal:2',
        ];
    }

    public function listing(): BelongsTo
    {
        return $this->belongsTo(Listing::class);
    }
}
