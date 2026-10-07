<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\ListListingsRequest;
use App\Http\Requests\Admin\ModerateListingRequest;
use App\Http\Requests\Admin\RejectListingRequest;
use App\Http\Resources\ListingResource;
use App\Models\Listing;
use App\Services\Admin\AdminListingService;
use Illuminate\Http\JsonResponse;

class ListingController extends Controller
{
    public function __construct(private readonly AdminListingService $listings)
    {
        //
    }

    /**
     * List livestock listings with optional search, filtering, and pagination.
     *
     * This is also the review surface. The returned rows already carry every
     * field a moderator needs — livestock type, breed, age, gender, weight,
     * quantity, price, location, health, vaccination, description, notes, seller
     * and dates — so the Admin Web renders a review from a row it has rather
     * than adding a detail endpoint that would be a second, divergent shape of
     * the same data.
     */
    public function index(ListListingsRequest $request): JsonResponse
    {
        $paginator = $this->listings->listListings(
            search: $request->validated('search'),
            livestockType: $request->validated('livestock_type'),
            status: $request->validated('status'),
            perPage: $request->validated('per_page', 15),
        );

        return response()->json([
            'success' => true,
            'data' => [
                'listings' => ListingResource::collection($paginator->items()),
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
     * Approve a pending listing.
     *
     * `pending → active` [D-02]. The response is the moderated listing in the
     * admin resource, so the screen that sent the request updates from the
     * server's own answer rather than from an optimistic guess.
     */
    public function approve(ModerateListingRequest $request, Listing $listing): JsonResponse
    {
        $approved = $this->listings->approve($listing);

        return response()->json([
            'success' => true,
            'message' => 'Listing approved successfully.',
            'data' => new ListingResource($approved),
        ], 200);
    }

    /**
     * Reject a pending listing.
     *
     * `pending → inactive` [D-02]. Not a new state: see
     * `AdminListingService::reject()`.
     *
     * `$adminNote` is the administrator's reason, stored on the row and returned
     * on the admin resource only.
     */
    public function reject(RejectListingRequest $request, Listing $listing): JsonResponse
    {
        $rejected = $this->listings->reject($listing, $request->validated('admin_note'));

        return response()->json([
            'success' => true,
            'message' => 'Listing rejected successfully.',
            'data' => new ListingResource($rejected),
        ], 200);
    }

    /**
     * Deactivate an active listing.
     *
     * `active → inactive` [D-02]. Sellers cannot reach this; it is admin-only
     * for the same reason the transition is [D-02 rule 4].
     */
    public function deactivate(ModerateListingRequest $request, Listing $listing): JsonResponse
    {
        $deactivated = $this->listings->deactivate($listing);

        return response()->json([
            'success' => true,
            'message' => 'Listing deactivated successfully.',
            'data' => new ListingResource($deactivated),
        ], 200);
    }
}
