<?php

namespace App\Http\Requests\Offer;

use App\Enums\InquiryCollectionMethod;
use App\Enums\InquiryPaymentMethod;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Body for a seller creating a purchase offer on a buyer's inquiry.
 *
 * The allow-list is exactly what the seller supplies: the inquiry, the
 * listing, and the proposed final price. `buyer_id`, `seller_id`, `status`
 * and `responded_at` are server-owned — the seller is the token, the buyer is
 * `inquiry.buyer_id`, and a new offer is always `pending` — so they are
 * refused with a 422 rather than silently dropped.
 *
 * `proposed_amount` is required and positive. It is the seller's proposed
 * final price, not the listing's asking price: the listing's asking price is
 * never copied into the offer, and the agreed price is stored independently
 * of any future listing price change.
 */
class StoreOfferRequest extends FormRequest
{
    public function authorize(): bool
    {
        // `auth:sanctum` + `ability:mobile`. The service re-checks that the
        // caller is the listing's seller and an approved seller.
        return true;
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'inquiry_id' => ['required', 'integer', 'exists:inquiries,id'],
            'listing_id' => ['required', 'integer', 'exists:listings,id'],
            'proposed_amount' => ['required', 'numeric', 'min:0.01'],
            // Legacy clients omit quantity and receive the inquiry's request.
            'proposed_quantity' => ['sometimes', 'integer', 'min:1', 'max:4294967295'],
            'proposed_pickup_date' => ['nullable', 'date', 'after_or_equal:today'],
            'payment_method' => [
                'nullable',
                'string',
                Rule::in(array_column(InquiryPaymentMethod::cases(), 'value')),
            ],
            'collection_method' => [
                'nullable',
                'string',
                Rule::in(array_column(InquiryCollectionMethod::cases(), 'value')),
            ],
            'note' => ['nullable', 'string', 'max:500'],

            'buyer_id' => ['prohibited'],
            'seller_id' => ['prohibited'],
            'status' => ['prohibited'],
            'responded_at' => ['prohibited'],
            'quantity' => ['prohibited'],
        ];
    }
}
