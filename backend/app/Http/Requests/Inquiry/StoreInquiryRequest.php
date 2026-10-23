<?php

namespace App\Http\Requests\Inquiry;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Body for creating a buyer inquiry from the mobile client.
 *
 * The allow-list is exactly the structured preferences the Inquire form
 * collects: `listing_id`, `message`, and the optional preference columns of
 * the `inquiries` table. `buyer_id`, `seller_id` and `status` are server-owned
 * — the buyer is the token, the seller is `listing.seller_id`, and an inquiry
 * is always created `open` — so they are refused with a 422 rather than
 * silently dropped: dropping them would hide a client bug, honouring them
 * would let a device choose its own counterparty or skip the workflow state.
 *
 * `message` carries the design document's 500-character ceiling (mobile
 * `AgroBenta_Inquiry_DESIGN.md` §3.3) so the server and the client's character
 * counter agree, and a whitespace-only message is refused rather than stored
 * as a blank inquiry.
 *
 * Every preference column is nullable by design ("a plain message remains a
 * valid inquiry" — `create_inquiries_table` migration), so only `message` is
 * required here.
 */
class StoreInquiryRequest extends FormRequest
{
    public function authorize(): bool
    {
        // `auth:sanctum` + `ability:mobile`. Any authenticated mobile user may
        // inquire; the service re-checks the listing's state and ownership.
        return true;
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'listing_id' => ['required', 'integer', 'exists:listings,id'],
            'message' => ['required', 'string', 'max:500', 'not_regex:/^\s*$/'],

            'subject' => ['nullable', 'string', 'max:255'],
            'purchase_interest' => ['nullable', 'boolean'],
            'transaction_method' => ['nullable', 'string', 'in:direct_deal,arrange_delivery'],
            'delivery_method' => ['nullable', 'string', 'max:255'],
            'delivery_fee' => ['nullable', 'numeric', 'min:0'],
            'contact_method' => ['nullable', 'string', 'in:in_app_message'],
            'preferred_schedule' => ['nullable', 'date'],

            'buyer_id' => ['prohibited'],
            'seller_id' => ['prohibited'],
            'status' => ['prohibited'],
        ];
    }
}
