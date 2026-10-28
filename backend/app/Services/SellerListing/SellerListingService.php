<?php

namespace App\Services\SellerListing;

use App\Enums\ActivityAction;
use App\Enums\ListingStatus;
use App\Http\Requests\SellerListing\SellerListingRules;
use App\Models\Listing;
use App\Models\User;
use App\Repositories\SellerListing\SellerListingRepository;
use App\Services\ActivityLogger;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use RuntimeException;

/**
 * The rules for what a seller may do to a listing, and from which state.
 *
 * The repository decides *which* rows are visible to a seller. This service
 * decides what may happen to them, and it is the only place that answers those
 * questions, because the answers are the documented lifecycle [D-02]:
 *
 *  - create produces a `draft`, never anything else;
 *  - `draft` becomes `pending` on submit, and that is the only way out of it;
 *  - `draft` and `active` are editable [D-24];
 *  - `draft` and `inactive` are destroyable [D-25];
 *  - `active → inactive` is an **administrator** action, and `sold` belongs to a
 *    transaction rather than a seller. Neither is reachable from here, and
 *    neither is approximated by anything this class does.
 *
 * A seller therefore cannot publish a listing. Approval is a moderation step this
 * phase does not implement (OQ-14), and no method below offers a substitute for
 * it.
 */
class SellerListingService
{
    use SellerListingRules;

    /**
     * The states a seller may still change the content of [D-24].
     *
     * `pending` is excluded because the listing is under review and changing it
     * mid-review is the seller's decision to make, not the reviewer's to
     * discover. `sold` is history. `inactive` was withdrawn and re-listing it is
     * a new listing, not an edit.
     *
     * @var list<ListingStatus>
     */
    private const EDITABLE_STATUSES = [ListingStatus::Draft, ListingStatus::Active];

    /**
     * The states a seller may destroy [D-25].
     *
     * `active` is not among them: a live listing is the seller's public promise,
     * and removing it from sale is a moderation decision, not a button.
     *
     * @var list<ListingStatus>
     */
    private const DELETABLE_STATUSES = [ListingStatus::Draft, ListingStatus::Inactive];

    public function __construct(
        private readonly SellerListingRepository $listingRepository,
        private readonly ActivityLogger $activity,
    ) {}

    /**
     * Find one of this seller's own listings, or null.
     *
     * The null covers both "no such listing" and "not yours", deliberately: the
     * controller turns either into the same 404 so a seller cannot learn that an
     * id belongs to somebody else.
     */
    public function findOwnedForSeller(int $listingId, User $seller): ?Listing
    {
        return $this->listingRepository->findOwned($listingId, $seller);
    }

    /**
     * List one seller's own listings, newest first.
     */
    public function listForSeller(
        User $seller,
        ?ListingStatus $status = null,
        ?string $search = null,
        int $perPage = 15,
    ): LengthAwarePaginator {
        return $this->listingRepository->paginateForSeller($seller, $status, $search, $perPage);
    }

    /**
     * Create a draft owned by this seller.
     *
     * `status` is `draft` because that is the only state a seller may put a
     * listing into [D-02 rule 1], and `seller_id` comes from the token.
     */
    public function create(User $seller, array $attributes): Listing
    {
        // A listing that does not exist yet has no directory to upload into and
        // no id to scope a filename to, so any supplied photo is a claim this
        // server cannot verify. A draft stays photo-optional: absent or `[]` is
        // valid, and the client uploads once the draft is saved (D-10).
        $photos = $attributes['photos'] ?? [];
        $photos = is_array($photos) ? $photos : [];

        if (Listing::normalisePhotoFilenames($photos) !== []) {
            throw ValidationException::withMessages([
                'photos' => 'Photos cannot be attached when a listing is created. Save the draft first, then upload photos.',
            ]);
        }

        return DB::transaction(function () use ($seller, $attributes): Listing {
            $listing = $this->listingRepository->createForSeller(
                $seller,
                $this->withStorageDefaults($attributes),
            );

            $this->activity->log(
                $seller,
                ActivityAction::ListingCreated,
                sprintf('Listing #%d created as a draft.', $listing->getKey()),
                [
                    'target_type' => 'listing',
                    'target_id' => $listing->getKey(),
                    'changes' => [
                        'status' => ['from' => null, 'to' => ListingStatus::Draft->value],
                    ],
                ],
            );

            return $listing;
        });
    }

    /**
     * Edit the content of a listing the seller owns.
     *
     * A `photos` value is accepted only when every name was actually uploaded
     * to this listing; see [validatedPhotoFilenames()].
     *
     * @throws ValidationException if the listing is not in an editable state or
     *                             a supplied photo is not stored on it
     */
    public function update(Listing $listing, array $attributes): Listing
    {
        $this->ensureStatusIs($listing, self::EDITABLE_STATUSES, 'Only a draft or an active listing can be edited.');

        if (array_key_exists('photos', $attributes)) {
            $attributes['photos'] = $this->validatedPhotoFilenames($listing, $attributes['photos']);
        }

        return DB::transaction(function () use ($listing, $attributes): Listing {
            $before = $listing->getAttributes();

            $updated = $this->listingRepository->update($listing, $attributes);

            $this->activity->log(
                $listing->seller_id,
                ActivityAction::ListingUpdated,
                sprintf('Listing #%d updated.', $listing->getKey()),
                [
                    'target_type' => 'listing',
                    'target_id' => $listing->getKey(),
                    'changes' => $this->changedAttributes(
                        $before,
                        $updated->getAttributes(),
                        array_keys($attributes),
                    ),
                ],
            );

            return $updated;
        });
    }

    /**
     * Move a draft into review.
     *
     * Re-validates the stored listing against the publication rules before
     * queueing it, as §5.4 requires: a draft that predates a rule change, or one
     * written outside this API, is rejected with 422 rather than being sent to a
     * moderator in a state the moderator cannot render. Those rules are
     * [SellerListingRules::submissionRules()] plus the photo minimum, which
     * applies at submission only [DEC-03]. A listing whose stored photo files
     * are missing from the disk is refused as well.
     *
     * @throws ValidationException if the stored listing is not submittable
     */
    public function submit(Listing $listing): Listing
    {
        $this->ensureSubmittable($listing);

        return DB::transaction(function () use ($listing): Listing {
            $previousStatus = $listing->status->value;

            $listing->status = ListingStatus::Pending;
            $listing->save();

            $this->activity->log(
                $listing->seller_id,
                ActivityAction::ListingSubmitted,
                sprintf('Listing #%d submitted for review.', $listing->getKey()),
                [
                    'target_type' => 'listing',
                    'target_id' => $listing->getKey(),
                    'changes' => [
                        'status' => ['from' => $previousStatus, 'to' => ListingStatus::Pending->value],
                    ],
                ],
            );

            return $listing;
        });
    }

    /**
     * Destroy a listing the seller owns.
     *
     * @throws ValidationException if the listing is not in a destroyable state
     */
    public function delete(Listing $listing): void
    {
        $this->ensureStatusIs($listing, self::DELETABLE_STATUSES, 'Only a draft or an inactive listing can be deleted.');

        DB::transaction(function () use ($listing): void {
            $targetId = $listing->getKey();
            $sellerId = $listing->seller_id;
            $previousStatus = $listing->status->value;
            $livestockType = $listing->livestock_type;

            $this->listingRepository->delete($listing);

            $this->activity->log(
                $sellerId,
                ActivityAction::ListingDeleted,
                sprintf('Listing #%d deleted.', $targetId),
                [
                    'target_type' => 'listing',
                    'target_id' => $targetId,
                    'context' => ['livestock_type' => $livestockType],
                    'changes' => ['status' => ['from' => $previousStatus, 'to' => null]],
                ],
            );
        });
    }

    /**
     * Add photos to a listing the seller owns.
     *
     * Files are written to the `listing-photos` disk under `listings/{id}/`
     * (functional documentation §4.5, D-10); only the generated filenames are
     * stored in the JSON column, and `MobileListingResource` turns them back
     * into absolute URLs on the way out.
     *
     * The per-listing ceiling is checked here, against the stored count,
     * rather than in the Form Request: the request sees only its own body, so
     * a cumulative limit is a service question — and checking it after the
     * controller's ownership lookup means an over-limit request from a
     * non-owner is a 404, never a 422 that confirms the listing exists.
     *
     * @param  array<int, UploadedFile>  $files
     *
     * @throws ValidationException if existing photos plus these files exceed the limit
     */
    public function addPhotos(Listing $listing, array $files): Listing
    {
        $this->ensureStatusIs(
            $listing,
            self::EDITABLE_STATUSES,
            'Photos can only be changed on a draft or an active listing.',
        );

        $stored = $listing->storedPhotoFilenames();
        $limit = $this->photoLimit();
        $previousCount = count($stored);

        if (count($stored) + count($files) > $limit) {
            throw ValidationException::withMessages([
                'photos' => 'A listing may have at most '.$limit.' photos.',
            ]);
        }

        $disk = Storage::disk(Listing::PHOTO_DISK);
        $directory = (string) $listing->getKey();

        foreach ($files as $file) {
            $filename = $file->hashName();

            // The disk is configured not to throw, so a failed write returns
            // false; that must not look like a successful upload until a buyer
            // discovers a broken image.
            if (! $disk->putFileAs($directory, $file, $filename)) {
                throw new RuntimeException('Failed to store a listing photo.');
            }

            $stored[] = $filename;
        }

        $updated = $this->listingRepository->update($listing, ['photos' => $stored]);

        // Same target/changes shape as the other listing writes, and written
        // only once the photos are actually stored and the row is updated, so a
        // refused or half-written upload can never be recorded as a success.
        // The files themselves are never named — only how many the listing
        // gained — so the audit holds no filename that could describe a stored
        // path.
        if ($files !== []) {
            $this->activity->log(
                $listing->seller_id,
                ActivityAction::ListingPhotoAdded,
                sprintf(
                    '%d %s added to listing #%d.',
                    count($files),
                    Str::plural('photo', count($files)),
                    $listing->getKey(),
                ),
                [
                    'target_type' => 'listing',
                    'target_id' => $listing->getKey(),
                    'changes' => [
                        'photos' => ['from' => $previousCount, 'to' => count($stored)],
                    ],
                ],
            );
        }

        return $updated;
    }

    /**
     * Remove one photo from a listing the seller owns.
     *
     * The client names the photo with the value it was served — the full URL
     * or the bare filename — and either collapses to the same filename, so a
     * client never has to parse its own URL to delete from it.
     *
     * An active listing may lose a photo but not its last one: publication
     * depends on at least one stored photo [DEC-03], so emptying a live
     * listing is a 409 rather than a valid edit.
     *
     * @throws ValidationException if the listing is not in an editable state
     */
    public function removePhoto(Listing $listing, string $photo): Listing
    {
        $this->ensureStatusIs(
            $listing,
            self::EDITABLE_STATUSES,
            'Photos can only be changed on a draft or an active listing.',
        );

        $filename = Listing::normalisePhotoFilename($photo) ?? '';
        $stored = $listing->storedPhotoFilenames();

        // 404, not 422: the listing is the seller's own, but a name that is
        // not on it names a photo that does not exist — the same absence as a
        // listing id that was never theirs.
        if (! in_array($filename, $stored, true)) {
            abort(404, 'Photo not found.');
        }

        // A published listing is approved on the strength of at least one
        // stored photo [DEC-03], so seller photo management must not be the
        // route that empties it. A draft may still lose its last photo.
        if ($listing->status === ListingStatus::Active && count($stored) === 1) {
            abort(409, 'The last photo of an active listing cannot be removed.');
        }

        $updated = DB::transaction(function () use ($listing, $filename, $stored): Listing {
            $updated = $this->listingRepository->update($listing, [
                'photos' => array_values(array_filter(
                    $stored,
                    static fn (string $stored): bool => $stored !== $filename,
                )),
            ]);

            $this->activity->log(
                $listing->seller_id,
                ActivityAction::ListingPhotoRemoved,
                sprintf('Photo removed from listing #%d.', $listing->getKey()),
                [
                    'target_type' => 'listing',
                    'target_id' => $listing->getKey(),
                    'context' => ['photo' => $filename],
                    'changes' => [
                        'photos' => ['from' => count($stored), 'to' => count($stored) - 1],
                    ],
                ],
            );

            return $updated;
        });

        // The database is the source of truth, so it is written before the
        // file is deleted: if the delete fails the worst case is an orphaned
        // file nothing references, while the reverse order would leave the
        // API advertising a photo that is gone.
        Storage::disk(Listing::PHOTO_DISK)->delete($listing->getKey().'/'.$filename);

        return $updated;
    }

    /**
     * Check the stored listing against the publication rules, on the model
     * itself.
     *
     * The data is the row, not the request, so a listing that could not be
     * created through this endpoint can still be caught before a moderator sees
     * it. Error keys are the column names, which is what the client's form is
     * built from. The photo minimum and the physical-file check are both applied
     * here, after the field rules, so an empty listing cannot reach review.
     *
     * @throws ValidationException
     */
    private function ensureSubmittable(Listing $listing): void
    {
        $validator = Validator::make(
            [
                'livestock_type' => $listing->livestock_type,
                'breed' => $listing->breed,
                // The `decimal:1` cast on the model turns a whole stored age into
                // the string "2.0", which the contract's `integer` rule would
                // reject even though nothing is wrong with the listing. An
                // integral value is therefore normalised back to an int before
                // validation; a genuinely fractional one is left exactly as it
                // is, so a row written outside this API with an age of 2.5 still
                // fails the rule instead of being silently truncated into
                // submittability.
                'age_value' => $this->wholeNumberOrNull($listing->age_value),
                'age_unit' => $listing->age_unit,
                'gender' => $listing->gender,
                // The `decimal:2` cast rounds on read, so a row that stores a
                // third decimal would look valid and slip past the rule DEC-02
                // exists to enforce. The raw stored value is what is validated;
                // the cast value is only a fallback for an unsaved attribute.
                'weight_value' => $listing->getRawOriginal('weight_value', $listing->weight_value),
                'weight_unit' => $listing->weight_unit,
                'quantity' => $listing->quantity,
                'asking_price' => $listing->getRawOriginal('asking_price', $listing->asking_price),
                'location' => $listing->location,
                'health_status' => $listing->health_status,
                'vaccination' => $listing->vaccination,
                'short_description' => $listing->short_description,
                'additional_notes' => $listing->additional_notes,
                'photos' => $listing->photos,
            ],
            // Publication, not merely submission: the photo minimum is a submit
            // action rule [DEC-03], so it belongs to the rule set rather than to
            // a check bolted on after it.
            $this->publicationRules(),
        );

        if ($validator->fails()) {
            throw ValidationException::withMessages($validator->errors()->toArray());
        }

        $this->ensureStatusIs(
            $listing,
            [ListingStatus::Draft],
            'Only a draft listing can be submitted for review.',
        );

        // The column is a declaration; the disk is the evidence. A row can name
        // a photo the upload endpoint never wrote, or one that has since been
        // removed by an operator or a storage lifecycle rule, and review must
        // not begin on images a buyer cannot load.
        if ($listing->missingPhotoFilenames() !== []) {
            throw ValidationException::withMessages([
                'photos' => 'One or more listing photos are missing. Remove and re-upload them before submitting.',
            ]);
        }
    }

    /**
     * Normalise a client-supplied photo list and require every filename to be
     * present in this listing's own directory.
     *
     * The column stores bare filenames and the directory is derived from the
     * listing's key, so a name the upload endpoint never wrote here is a claim
     * the API cannot honour — including a filename that belongs to another
     * listing. The whole set is compared against one directory listing, so a
     * client that echoes the URL it was served still round-trips losslessly.
     *
     * A `photos` edit that empties an active listing is refused for the same
     * reason removal of its last photo is: a published listing must keep at
     * least one photo [DEC-03], and an edit is not a route around that rule.
     *
     * @return list<string>
     *
     * @throws ValidationException if a name is not stored on this listing
     */
    private function validatedPhotoFilenames(Listing $listing, mixed $photos): array
    {
        $filenames = Listing::normalisePhotoFilenames(is_array($photos) ? $photos : []);

        if ($filenames === []) {
            if ($listing->status === ListingStatus::Active) {
                throw ValidationException::withMessages([
                    'photos' => 'An active listing must keep at least one photo.',
                ]);
            }

            return [];
        }

        if (array_diff($filenames, $listing->photoFilenamesOnDisk()) !== []) {
            throw ValidationException::withMessages([
                'photos' => 'Only photos uploaded to this listing can be saved. Upload the photo first.',
            ]);
        }

        return $filenames;
    }

    /**
     * Normalise a stored numeric value to int, but only when it is a whole
     * number.
     *
     * Null, a fraction, or a non-numeric string is returned unchanged, so the
     * `integer` rule keeps rejecting those; only the cast artefact ("2.0" for
     * a perfectly integral age) is repaired.
     */
    private function wholeNumberOrNull(mixed $value): mixed
    {
        if ($value === null || ! is_numeric($value)) {
            return $value;
        }

        $numeric = (float) $value;

        // Loose comparison on purpose: the question is numeric equality with
        // its integer self, not type identity.
        return (int) $numeric == $numeric ? (int) $numeric : $value;
    }

    /**
     * Guard a lifecycle transition on the listing's current state.
     *
     * @param  list<ListingStatus>  $allowed
     *
     * @throws ValidationException
     */
    private function ensureStatusIs(Listing $listing, array $allowed, string $message): void
    {
        if (in_array($listing->status, $allowed, true)) {
            return;
        }

        // 409, not 422: nothing about the request is malformed, the listing is
        // simply in a state where this action has no meaning [D-02 rule 12].
        abort(409, $message);
    }

    /**
     * Supply values for the columns that cannot be null.
     *
     * Three contract-optional fields are `NOT NULL` with no database default:
     * `breed`, `short_description` and `photos`. An empty string is the honest
     * representation of "the seller has not written this yet" for the two text
     * fields, and an empty array for `photos` is what the contract already
     * specifies as the default. `weight_unit` has a database default, but it is
     * filled here too so the response reflects it before a reload.
     *
     * @param  array<string, mixed>  $attributes
     * @return array<string, mixed>
     */
    private function withStorageDefaults(array $attributes): array
    {
        $attributes['breed'] ??= '';
        $attributes['short_description'] ??= '';
        $attributes['photos'] ??= [];
        $attributes['weight_unit'] ??= 'kg';

        return $attributes;
    }

    /**
     * Before/after pairs for the attributes a write actually changed.
     *
     * Only keys that differ are returned, so the audit records a real edit
     * rather than echoing the whole request. `photos` is reported as a count:
     * the stored value is a JSON array of filenames, and a reordering is not a
     * meaningful change to the listing.
     *
     * @param  array<string, mixed>  $before
     * @param  array<string, mixed>  $after
     * @param  list<string>  $keys
     * @return array<string, array{from: mixed, to: mixed}>
     */
    private function changedAttributes(array $before, array $after, array $keys): array
    {
        $changes = [];

        foreach ($keys as $key) {
            $old = $before[$key] ?? null;
            $new = $after[$key] ?? null;

            if ($key === 'photos') {
                $oldCount = $this->photoCount($old);
                $newCount = $this->photoCount($new);

                if ($oldCount !== $newCount) {
                    $changes['photos'] = ['from' => $oldCount, 'to' => $newCount];
                }

                continue;
            }

            if ($old !== $new) {
                $changes[$key] = ['from' => $old, 'to' => $new];
            }
        }

        return $changes;
    }

    /**
     * Count the filenames in a stored `photos` value, whether it arrives as the
     * raw JSON string from the attributes array or an already-decoded array.
     */
    private function photoCount(mixed $value): int
    {
        if (is_string($value)) {
            $value = json_decode($value, true);
        }

        return is_array($value) ? count($value) : 0;
    }
}
