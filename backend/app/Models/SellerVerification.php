<?php

namespace App\Models;

use App\Enums\SellerVerificationStatus as Status;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Str;

#[Fillable([
    'user_id', 'phone', 'address', 'business_name', 'business_location', 'business_description',
    'id_document_ref', 'government_id_type', 'government_id_description',
    'has_no_back_image', 'id_document_path', 'id_document_front_path',
    'id_document_back_path', 'selfie_path', 'proof_of_address_path',
    'farm_photo_paths', 'status', 'admin_note', 'reviewed_by', 'reviewed_at',
    'submitted_at',
])]
class SellerVerification extends Model
{
    /**
     * Get the attributes that should be cast.
     *
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'status' => Status::class,
            'farm_photo_paths' => 'array',
            'has_no_back_image' => 'boolean',
            'submitted_at' => 'datetime',
            'reviewed_at' => 'datetime',
        ];
    }

    public function seller(): BelongsTo
    {
        return $this->belongsTo(User::class, 'user_id')->withTrashed();
    }

    public function reviewer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'reviewed_by')->withTrashed();
    }

    public function isOpen(): bool
    {
        return $this->status->isOpen();
    }

    /**
     * The ids that name this record's farm photos in the API. An id is the
     * random part of the filename, so it reveals nothing about the storage path.
     *
     * @return list<string>
     */
    public function farmPhotoIds(): array
    {
        return array_map(
            fn (string $path): string => Str::after(pathinfo($path, PATHINFO_FILENAME), 'farm_photo_'),
            $this->farm_photo_paths ?? [],
        );
    }
}
