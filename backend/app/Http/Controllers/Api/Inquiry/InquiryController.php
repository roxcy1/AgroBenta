<?php

namespace App\Http\Controllers\Api\Inquiry;

use App\Http\Controllers\Controller;
use App\Http\Requests\Inquiry\IndexInquiryRequest;
use App\Http\Requests\Inquiry\StoreInquiryRequest;
use App\Http\Resources\InquiryListItemResource;
use App\Http\Resources\MobileInquiryResource;
use App\Models\Listing;
use App\Services\Inquiry\InquiryService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Create a buyer inquiry — the mobile write path.
 *
 * Received inquiries are read through the seller endpoint. There is no
 * administrator inquiry route: an inquiry is between the buyer and the seller
 * only (functional documentation §8.2). Every method
 * resolves the buyer from the token and the seller from the listing — never
 * from the body — so there is no parameter or field that could point an
 * inquiry at the wrong account.
 *
 * Responses use `MobileInquiryResource`, which carries neither party's email
 * address: a mobile reader must not receive them (functional documentation
 * §10.4).
 */
class InquiryController extends Controller
{
    public function __construct(private readonly InquiryService $inquiries)
    {
        //
    }

    /**
     * `GET /api/inquiries` — the caller's active inquiries.
     *
     * Backs the Messages "Inquiries" tab. The scope is the token; `role`
     * only selects which side of the caller's own records to return. An
     * inquiry whose offer was accepted is excluded — that agreement belongs
     * to the Transactions tab and must never be offered again.
     */
    public function index(IndexInquiryRequest $request): JsonResponse
    {
        $role = $request->validated('role');

        $inquiries = $this->inquiries->activeFor($request->user(), $role);

        return response()->json([
            'success' => true,
            'data' => [
                'inquiries' => InquiryListItemResource::collection($inquiries),
            ],
        ], 200);
    }

    /**
     * The authenticated buyer's inquiry about [listing], or `data: null`.
     *
     * The pre-check the Inquire screen runs before it renders the form: an
     * inquiry already sent - in any status - is shown as "Inquiry Already
     * Sent" instead of a second form. Buyer-scoped from the token, so no query
     * parameter can read another buyer's record.
     *
     * The listing is route-model bound, so an id that does not exist is a 404
     * from Laravel. A listing the buyer has not asked about is a normal `null`,
     * not an error.
     */
    public function existing(Request $request, Listing $listing): JsonResponse
    {
        $inquiry = $this->inquiries->findForBuyerAndListing(
            $request->user(),
            $listing,
        );

        return response()->json([
            'success' => true,
            'data' => $inquiry === null
                ? null
                : new MobileInquiryResource($inquiry),
        ]);
    }

    /**
     * Store an inquiry about a listing for the authenticated buyer.
     *
     * The listing lookup answers 404 for an id that does not exist; a listing
     * that exists but is not open to inquiries is a 409 raised by the service.
     */
    public function store(StoreInquiryRequest $request): JsonResponse
    {
        $listing = Listing::query()->find($request->validated('listing_id'));

        if ($listing === null) {
            abort(404, 'Listing not found.');
        }

        $inquiry = $this->inquiries->create(
            $request->user(),
            $listing,
            $request->validated('message'),
            $request->safe()->only([
                'subject',
                'purchase_interest',
                'transaction_method',
                'delivery_method',
                'delivery_fee',
                'contact_method',
                'preferred_schedule',
                'collection_date_option',
                'payment_method',
                'collection_method',
            ]),
            (int) ($request->validated('requested_quantity') ?? 1),
        );

        return response()->json([
            'success' => true,
            'message' => 'Inquiry sent.',
            'data' => new MobileInquiryResource($inquiry),
        ], 201);
    }
}
