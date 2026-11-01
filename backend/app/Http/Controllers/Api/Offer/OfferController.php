<?php

namespace App\Http\Controllers\Api\Offer;

use App\Enums\OfferStatus;
use App\Http\Controllers\Controller;
use App\Http\Requests\Offer\IndexOfferRequest;
use App\Http\Requests\Offer\StoreOfferRequest;
use App\Http\Resources\MobileTransactionResource;
use App\Http\Resources\OfferResource;
use App\Repositories\Offer\OfferRepository;
use App\Services\Offer\OfferService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Purchase offers made by a seller to a buyer within a buyer–seller
 * conversation.
 *
 * Every method resolves the user from the token — never from the body or the
 * query. An offer is visible only to its buyer and its seller.
 */
class OfferController extends Controller
{
    public function __construct(
        private readonly OfferService $offers,
        private readonly OfferRepository $offerRepository,
    ) {
        //
    }

    /**
     * `GET /api/offers` — the caller's offers, newest first.
     *
     * The list is always scoped to the token. `inquiry_id`, `listing_id`,
     * `counterpart_id` and `status` narrow that list; none can widen it.
     */
    public function index(IndexOfferRequest $request): JsonResponse
    {
        $status = $request->validated('status');

        $offers = $this->offers->list(
            $request->user(),
            $request->validated('inquiry_id') === null
                ? null
                : (int) $request->validated('inquiry_id'),
            $request->validated('counterpart_id') === null
                ? null
                : (int) $request->validated('counterpart_id'),
            $request->validated('listing_id') === null
                ? null
                : (int) $request->validated('listing_id'),
            $status === null ? null : OfferStatus::from($status),
        );

        return response()->json([
            'success' => true,
            'data' => [
                'offers' => OfferResource::collection($offers),
            ],
        ], 200);
    }

    /**
     * `POST /api/offers` — create a purchase offer.
     *
     * The seller is the authenticated user; the buyer and listing are derived
     * from the inquiry inside the service.
     */
    public function store(StoreOfferRequest $request): JsonResponse
    {
        $offer = $this->offers->create(
            $request->user(),
            (int) $request->validated('inquiry_id'),
            (int) $request->validated('listing_id'),
            (string) $request->validated('proposed_amount'),
        );

        return response()->json([
            'success' => true,
            'message' => 'Offer created.',
            'data' => new OfferResource($offer),
        ], 201);
    }

    /**
     * `GET /api/offers/{offer}` — view one offer the caller is party to.
     */
    public function show(Request $request, string $offer): JsonResponse
    {
        $found = $this->offerRepository->findForUser((int) $offer, $request->user());

        if ($found === null) {
            abort(404, 'Offer not found.');
        }

        return response()->json([
            'success' => true,
            'data' => new OfferResource($found),
        ], 200);
    }

    /**
     * `POST /api/offers/{offer}/accept` — buyer accepts, creating a transaction.
     *
     * The response carries both the accepted offer and the transaction the
     * acceptance created, so the client can show the new record without a
     * second request.
     */
    public function accept(Request $request, string $offer): JsonResponse
    {
        $result = $this->offers->accept((int) $offer, $request->user());

        return response()->json([
            'success' => true,
            'message' => 'Offer accepted.',
            'data' => [
                'offer' => new OfferResource($result['offer']),
                'transaction' => new MobileTransactionResource(
                    $result['transaction']->load(['listing', 'buyer', 'seller']),
                ),
            ],
        ], 200);
    }

    /**
     * `POST /api/offers/{offer}/decline` — buyer declines.
     */
    public function decline(Request $request, string $offer): JsonResponse
    {
        $declined = $this->offers->decline((int) $offer, $request->user());

        return response()->json([
            'success' => true,
            'message' => 'Offer declined.',
            'data' => new OfferResource($declined),
        ], 200);
    }

    /**
     * `POST /api/offers/{offer}/withdraw` — seller withdraws their own offer.
     */
    public function withdraw(Request $request, string $offer): JsonResponse
    {
        $withdrawn = $this->offers->withdraw((int) $offer, $request->user());

        return response()->json([
            'success' => true,
            'message' => 'Offer withdrawn.',
            'data' => new OfferResource($withdrawn),
        ], 200);
    }
}
