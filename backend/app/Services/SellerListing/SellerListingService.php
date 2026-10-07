<?php

namespace App\Services\SellerListing;

use App\Enums\ListingStatus;
use App\Http\Requests\SellerListing\SellerListingRules;
use App\Models\Listing;
use App\Models\User;
use App\Repositories\SellerListing\SellerListingRepository;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\ValidationException;

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
        return $this->listingRepository->createForSeller(
            $seller,
            $this->withStorageDefaults($attributes),
        );
    }

    /**
     * Edit the content of a listing the seller owns.
     *
     * @throws ValidationException if the listing is not in an editable state
     */
    public function update(Listing $listing, array $attributes): Listing
    {
        $this->ensureStatusIs($listing, self::EDITABLE_STATUSES, 'Only a draft or an active listing can be edited.');

        return $this->listingRepository->update($listing, $attributes);
    }

    /**
     * Move a draft into review.
     *
     * Re-validates the stored listing against the create rules before queueing
     * it, as §5.4 requires: a draft that predates a rule change, or one written
     * outside this API, is rejected with 422 rather than being sent to a moderator
     * in a state the moderator cannot render.
     *
     * @throws ValidationException if the stored listing is not submittable
     */
    public function submit(Listing $listing): Listing
    {
        $this->ensureSubmittable($listing);

        $listing->status = ListingStatus::Pending;
        $listing->save();

        return $listing;
    }

    /**
     * Destroy a listing the seller owns.
     *
     * @throws ValidationException if the listing is not in a destroyable state
     */
    public function delete(Listing $listing): void
    {
        $this->ensureStatusIs($listing, self::DELETABLE_STATUSES, 'Only a draft or an inactive listing can be deleted.');

        $this->listingRepository->delete($listing);
    }

    /**
     * Check the stored listing against the create rules, on the model itself.
     *
     * The data is the row, not the request, so a listing that could not be
     * created through this endpoint can still be caught before a moderator sees
     * it. Error keys are the column names, which is what the client's form is
     * built from.
     *
     * @throws ValidationException
     */
    private function ensureSubmittable(Listing $listing): void
    {
        $validator = Validator::make(
            [
                'livestock_type' => $listing->livestock_type,
                'breed' => $listing->breed,
                'age_value' => $listing->age_value,
                'age_unit' => $listing->age_unit,
                'gender' => $listing->gender,
                'weight_value' => $listing->weight_value,
                'weight_unit' => $listing->weight_unit,
                'quantity' => $listing->quantity,
                'asking_price' => $listing->asking_price,
                'location' => $listing->location,
                'health_status' => $listing->health_status,
                'vaccination' => $listing->vaccination,
                'short_description' => $listing->short_description,
                'additional_notes' => $listing->additional_notes,
                'photos' => $listing->photos,
            ],
            $this->submissionRules(),
        );

        if ($validator->fails()) {
            throw ValidationException::withMessages($validator->errors()->toArray());
        }

        $this->ensureStatusIs(
            $listing,
            [ListingStatus::Draft],
            'Only a draft listing can be submitted for review.',
        );
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
}
