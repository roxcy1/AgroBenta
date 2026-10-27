<?php

namespace App\Http\Controllers\Api\Inquiry;

use App\Http\Controllers\Controller;
use App\Http\Requests\Inquiry\StoreInquiryRequest;
use App\Http\Resources\MobileInquiryResource;
use App\Models\Listing;
use App\Services\Inquiry\InquiryService;
use Illuminate\Http\JsonResponse;

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
            ]),
        );

        return response()->json([
            'success' => true,
            'message' => 'Inquiry sent.',
            'data' => new MobileInquiryResource($inquiry),
        ], 201);
    }
}
