<?php

namespace App\Http\Controllers\Api\SellerListing;

use App\Enums\ListingStatus;
use App\Http\Controllers\Controller;
use App\Http\Requests\SellerListing\IndexSellerListingRequest;
use App\Http\Requests\SellerListing\SellerListingActionRequest;
use App\Http\Requests\SellerListing\StoreSellerListingRequest;
use App\Http\Requests\SellerListing\UpdateSellerListingRequest;
use App\Http\Resources\MobileListingResource;
use App\Models\Listing;
use App\Models\User;
use App\Services\SellerListing\SellerListingService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * A seller's own listing management.
 *
 * Read/write, and the only write path a seller has. Every method resolves the
 * seller from the token — never from the body or the query — and returns
 * `MobileListingResource`, so a seller sees the same projection of their own
 * listing that a buyer would see if it were active. The administrator-facing
 * `ListingResource` is never used here.
 *
 * The lifecycle itself is not in this class. It belongs to
 * [SellerListingService], which is the only place that knows a draft may be
 * submitted, that an active listing may be edited, and that a seller cannot
 * publish, deactivate or mark anything sold. A controller that also decided those
 * things would be a second, divergent copy of [D-02].
 */
class SellerListingController extends Controller
{
    public function __construct(private readonly SellerListingService $listings)
    {
        //
    }

    /**
     * List the authenticated seller's own listings, in every status.
     *
     * Unlike the marketplace, `status` is a permitted filter: a seller needs to
     * find their drafts and their listings awaiting review, which are exactly the
     * records the marketplace never returns [D-02 rule 9].
     */
    public function index(IndexSellerListingRequest $request): JsonResponse
    {
        $status = $request->validated('status');

        $paginator = $this->listings->listForSeller(
            seller: $this->seller($request),
            // The `in:` rule has already proved the value is one of the five, so
            // the only way this throws is a status added to the enum without being
            // added to the filter — and that is the safe direction to fail in.
            status: $status === null ? null : ListingStatus::from($status),
            search: $request->validated('search'),
            perPage: (int) $request->validated('per_page', 15),
        );

        return response()->json([
            'success' => true,
            'data' => [
                'listings' => MobileListingResource::collection($paginator->items()),
                'pagination' => [
                    'current_page' => $paginator->currentPage(),
                    'last_page' => $paginator->lastPage(),
                    'per_page' => $paginator->perPage(),
                    'total' => $paginator->total(),
                ],
            ],
        ], 200);
    }

    /**
     * Create a draft listing.
     */
    public function store(StoreSellerListingRequest $request): JsonResponse
    {
        $listing = $this->listings->create($this->seller($request), $request->validated());

        return response()->json([
            'success' => true,
            'message' => 'Listing saved as a draft.',
            'data' => new MobileListingResource($listing),
        ], 201);
    }

    /**
     * Edit a listing the seller owns.
     */
    public function update(UpdateSellerListingRequest $request, string $listing): JsonResponse
    {
        $updated = $this->listings->update(
            $this->findOwnedListing($request, $listing),
            $request->validated(),
        );

        return response()->json([
            'success' => true,
            'message' => 'Listing updated.',
            'data' => new MobileListingResource($updated),
        ], 200);
    }

    /**
     * Submit a draft for review.
     *
     * This is the furthest a seller can move a listing. Promotion to `active` is
     * an administrator decision, so the response says `pending` and stops there.
     */
    public function submit(SellerListingActionRequest $request, string $listing): JsonResponse
    {
        $submitted = $this->listings->submit($this->findOwnedListing($request, $listing));

        return response()->json([
            'success' => true,
            'message' => 'Listing submitted for review.',
            'data' => new MobileListingResource($submitted),
        ], 200);
    }

    /**
     * Destroy a draft or withdrawn listing.
     */
    public function destroy(SellerListingActionRequest $request, string $listing): JsonResponse
    {
        $this->listings->delete($this->findOwnedListing($request, $listing));

        return response()->json([
            'success' => true,
            'message' => 'Listing deleted.',
        ], 200);
    }

    /**
     * The authenticated seller.
     *
     * The `seller` middleware has already proved `isApprovedSeller()`; this only
     * reads the identity that check was performed against, so the seller whose
     * listings are being managed cannot differ from the seller they are scoped to.
     */
    private function seller(Request $request): User
    {
        return $request->user();
    }

    /**
     * Resolve a listing the authenticated seller owns, or 404.
     *
     * A listing owned by somebody else and a listing that does not exist are
     * indistinguishable from here, so one seller cannot probe another's inventory
     * by watching status codes.
     */
    private function findOwnedListing(Request $request, string $listing): Listing
    {
        $owned = $this->listings->findOwnedForSeller((int) $listing, $this->seller($request));

        if ($owned === null) {
            abort(404, 'Listing not found.');
        }

        return $owned;
    }
}
