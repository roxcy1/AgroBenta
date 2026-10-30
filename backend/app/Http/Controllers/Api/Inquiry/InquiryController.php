<?php

namespace App\Http\Controllers\Api\Inquiry;

use App\Http\Controllers\Controller;
use App\Http\Requests\Inquiry\StoreInquiryRequest;
use App\Http\Resources\MobileInquiryResource;
use App\Models\Listing;
use App\Services\Inquiry\InquiryService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Create a buyer inquiry — the mobile write path.
 *
 * Received inquiries are read through the seller endpoint; triaging and
 * re-statusing belong to the Admin Web's flow under `/admin/inquiries*`. This
 * controller exists because that block's route comment reserves creation for
 * the buyer's mobile client. Every method
 * resolves the buyer from the token and the seller from the listing — never
 * from the body — so there is no parameter or field that could point an
 * inquiry at the wrong account.
 *
 * Responses use `MobileInquiryResource`, never the administrator-facing
 * `InquiryResource`: the admin projection carries both parties' email
 * addresses, and a mobile reader must not receive them (functional
 * documentation §10.4).
 */
class InquiryController extends Controller
{
    public function __construct(private readonly InquiryService $inquiries)
    {
        //
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
        );

        return response()->json([
            'success' => true,
            'message' => 'Inquiry sent.',
            'data' => new MobileInquiryResource($inquiry),
        ], 201);
    }
}
