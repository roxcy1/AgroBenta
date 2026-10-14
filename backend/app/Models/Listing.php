<?php

namespace App\Models;

use App\Enums\ListingStatus;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Facades\Storage;

#[Fillable([
    'seller_id', 'livestock_type', 'breed', 'age_value', 'age_unit',
    'gender', 'weight_value', 'weight_unit', 'quantity', 'asking_price',
    'location', 'health_status', 'vaccination', 'short_description',
    'additional_notes', 'photos', 'status', 'admin_note',
])]
class Listing extends Model
{
    /**
     * The storage disk listing photos are written to and served from.
     *
     * Named here rather than hard-coded at each call site so a deployment can
     * point photos at a different disk (config `filesystems.disks`) without
     * touching model logic — see `config/filesystems.php`.
     */
    public const PHOTO_DISK = 'listing-photos';

    /**
     * The most photos one listing may carry, across every write path.
     *
     * The approved ceiling (contract §4.5.2): uploads append to it, the
     * create/update `photos` field sets it in one go, and both consult this
     * single number so the two paths cannot drift apart.
     */
    public const PHOTO_LIMIT = 10;

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
            'age_value' => 'decimal:1',
            'weight_value' => 'decimal:2',
            'asking_price' => 'decimal:2',
        ];
    }

    /**
     * Store photo *filenames* in the JSON column — never a path or a URL.
     *
     * [SEC] §4.5 / D-10 (read- and write-side representation): the column holds
     * bare filenames such as `x7Kd9f…a2.jpg`; the `listings/{id}/` directory and
     * the URL scheme are derived at read time. That is what lets this ticket
     * change disks or hosting without a migration — the column is sufficient.
     *
     * `basename()` is the entire normalisation and it is deliberately
     * forgiving: a client may echo the URL it was handed by the API, send a
     * storage-relative path, or send a bare filename — all three collapse to
     * the filename, so a read-modify-write round trip is lossless. `../`
     * traversal cannot survive it, and non-string or empty entries are dropped
     * rather than persisted (the API boundary rejects them with a 422 before
     * reaching here; this is the model's own defence for direct writes).
     *
     * A classic set-mutator replaces the cast entirely — the connection
     * returns before the `array` cast runs — so this method writes the JSON
     * itself; that write is the persisted value.
     *
     * @return list<string>
     */
    protected function setPhotosAttribute(mixed $value): array
    {
        $filenames = [];

        foreach (is_array($value) ? $value : [] as $photo) {
            if (! is_string($photo) || trim($photo) === '') {
                continue;
            }

            $filename = basename(str_replace('\\', '/', trim($photo)));

            if ($filename !== '' && $filename !== '.' && $filename !== '..') {
                $filenames[] = $filename;
            }
        }

        $filenames = array_values(array_unique($filenames));

        $this->attributes['photos'] = json_encode($filenames);

        return $filenames;
    }

    /**
     * Return photo URLs — never filenames, never storage-relative paths.
     *
     * The read half of D-10: the mobile client receives absolute, fetchable
     * URLs built by the `listing-photos` disk's URL scheme. A mobile client
     * cannot resolve `storage/app/public/…`, so no stored relative value ever
     * leaves this model. With no key there is no directory to derive, so an
     * unsaved model reports no photos rather than an unresolvable path.
     *
     * A get-mutator runs instead of the cast on read, so the raw JSON string
     * arrives here; an already-decoded array is accepted too, so behaviour is
     * identical regardless of cast ordering.
     *
     * @return list<string>
     */
    protected function getPhotosAttribute(mixed $value): array
    {
        $photos = is_string($value) ? json_decode($value, true) : $value;

        if (! is_array($photos) || $this->getKey() === null) {
            return [];
        }

        $disk = Storage::disk(self::PHOTO_DISK);
        $directory = (string) $this->getKey();

        return array_values(array_map(
            static fn (string $filename): string => $disk->url($directory.'/'.$filename),
            array_filter($photos, 'is_string'),
        ));
    }

    /**
     * The stored photo filenames — the raw form, without URL resolution.
     *
     * The storage-side counterpart of `$listing->photos`, for code that must
     * compare against what is actually on disk (the per-listing photo limit,
     * deletion by filename) rather than what clients are shown. Reads the
     * attribute as it will be persisted, so the URL accessor cannot leak into
     * those comparisons.
     *
     * @return list<string>
     */
    public function storedPhotoFilenames(): array
    {
        $raw = $this->attributes['photos'] ?? null;
        $photos = is_string($raw) ? json_decode($raw, true) : $raw;

        if (! is_array($photos)) {
            return [];
        }

        return array_values(array_filter($photos, 'is_string'));
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
