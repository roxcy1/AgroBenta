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
     * The canonical stored form of one client-supplied photo value.
     *
     * `basename()` is the entire normalisation and it is deliberately
     * forgiving: a client may echo the URL it was handed by the API, send a
     * storage-relative path, or send a bare filename — all three collapse to
     * the filename, so a read-modify-write round trip is lossless. `../`
     * traversal cannot survive it.
     *
     * Returns null for a value that carries no filename at all, so callers can
     * drop it rather than persist an empty entry.
     */
    public static function normalisePhotoFilename(string $photo): ?string
    {
        $filename = basename(str_replace('\\', '/', trim($photo)));

        return in_array($filename, ['', '.', '..'], true) ? null : $filename;
    }

    /**
     * The canonical stored form of a client-supplied photo list.
     *
     * The single definition of the write-side representation, shared by the
     * mutator below and by `SellerListingService`, so the filenames a service
     * checks against storage are exactly the filenames that will be persisted.
     *
     * @param  array<int, mixed>  $photos
     * @return list<string>
     */
    public static function normalisePhotoFilenames(array $photos): array
    {
        $filenames = [];

        foreach ($photos as $photo) {
            if (! is_string($photo)) {
                continue;
            }

            $filename = self::normalisePhotoFilename($photo);

            if ($filename !== null) {
                $filenames[] = $filename;
            }
        }

        return array_values(array_unique($filenames));
    }

    /**
     * Store photo *filenames* in the JSON column — never a path or a URL.
     *
     * [SEC] §4.5 / D-10 (read- and write-side representation): the column holds
     * bare filenames such as `x7Kd9f…a2.jpg`; the `listings/{id}/` directory and
     * the URL scheme are derived at read time. That is what lets this ticket
     * change disks or hosting without a migration — the column is sufficient.
     *
     * Non-string or empty entries are dropped rather than persisted (the API
     * boundary rejects them with a 422 before reaching here; this is the
     * model's own defence for direct writes).
     *
     * A classic set-mutator replaces the cast entirely — the connection
     * returns before the `array` cast runs — so this method writes the JSON
     * itself; that write is the persisted value.
     *
     * @return list<string>
     */
    protected function setPhotosAttribute(mixed $value): array
    {
        $filenames = self::normalisePhotoFilenames(is_array($value) ? $value : []);

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

    /**
     * Whether at least one photo is stored on this listing.
     *
     * Reads the persisted JSON column rather than `$listing->photos`, which is
     * a list of absolute URLs built for clients: the DEC-03 photo rule is about
     * what the server actually stored, not about a URL list a caller could
     * supply. A draft may have none; submission for review and administrator
     * approval both require one (functional documentation §4.5).
     */
    public function hasStoredPhotos(): bool
    {
        return $this->storedPhotoFilenames() !== [];
    }

    /**
     * The filenames that actually exist in this listing's photo directory.
     *
     * One directory listing for the whole record — never an `exists()` call per
     * filename — so ten photos cost one filesystem read locally and one request
     * on a remote disk. An unsaved model has no directory to read.
     *
     * @return list<string>
     */
    public function photoFilenamesOnDisk(): array
    {
        if ($this->getKey() === null) {
            return [];
        }

        return array_values(array_map(
            static fn (string $path): string => basename($path),
            Storage::disk(self::PHOTO_DISK)->files((string) $this->getKey()),
        ));
    }

    /**
     * The stored photo filenames with no matching file on the photo disk.
     *
     * The persisted JSON column is a declaration; this is the only method that
     * checks it against storage. A failed read is indistinguishable from an
     * empty directory, so the caller fails closed rather than admitting a
     * listing whose images may be dead (functional documentation §4.5).
     *
     * @return list<string>
     */
    public function missingPhotoFilenames(): array
    {
        return array_values(array_diff(
            $this->storedPhotoFilenames(),
            $this->photoFilenamesOnDisk(),
        ));
    }

    /**
     * A short, human-readable name for this listing.
     *
     * A listing has no `title` column: the seller supplies a species and a
     * breed, and the breed is the more specific of the two. `breed` is
     * non-null but may be blank, so the species is the fallback rather than an
     * empty label. The approval and rejection notifications both name the same
     * record, so they resolve the label here instead of each carrying its own
     * copy of the rule.
     */
    public function displayLabel(): string
    {
        $breed = trim((string) $this->breed);

        return $breed === '' ? (string) $this->livestock_type : $breed;
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
