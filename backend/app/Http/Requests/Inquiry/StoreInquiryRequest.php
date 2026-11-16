<?php

namespace App\Http\Requests\Inquiry;

use App\Enums\InquiryCollectionMethod;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Support\Carbon;
use Illuminate\Validation\Rule;

/**
 * Body for creating a buyer inquiry from the mobile client.
 *
 * The allow-list is exactly the structured preferences the Inquire form
 * collects: `listing_id`, the two required preferences (`payment_method`,
 * `collection_method`), and the remaining optional fields of the `inquiries`
 * table. `buyer_id`, `seller_id` and `status` are server-owned — the buyer is
 * the token, the seller is `listing.seller_id`, and an inquiry is always
 * created `open` — so they are refused with a 422 rather than silently dropped.
 *
 * `message` and `collection_date_option` are optional. When a message is
 * supplied it carries the 500-character ceiling and may not be whitespace-only.
 * When a date option requests a concrete date, `preferred_schedule` is required
 * and may not be in the past.
 *
 * `payment_method` and `collection_method` remain required. The collection
 * rule accepts the four current choices plus the legacy `discuss_with_seller`
 * value so older app builds do not break; the current form never offers it.
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
            // Older mobile builds omit this field and continue to request one
            // head. The service applies that compatibility default.
            'requested_quantity' => ['sometimes', 'integer', 'min:1', 'max:4294967295'],
            'message' => ['nullable', 'string', 'max:500', 'not_regex:/^\s*$/'],
            'collection_date_option' => [
                'nullable',
                'string',
                'in:specific_date,next_few_days,this_week',
            ],
            'preferred_schedule' => [
                Rule::requiredIf(fn () => in_array(
                    $this->input('collection_date_option'),
                    ['specific_date', 'next_few_days'],
                )),
                'date',
                function ($attribute, $value, $fail) {
                    $option = request()->input('collection_date_option');
                    $today = now()->startOfDay();
                    $tomorrow = $today->copy()->addDay();
                    $day3 = $today->copy()->addDays(3);

                    if (is_null($value)) {
                        // Presence is enforced by required_if above; nothing more.
                        return;
                    }

                    $date = Carbon::parse($value)->startOfDay();

                    if ($option === 'specific_date') {
                        if ($date->lt($today)) {
                            $fail('The preferred schedule cannot be a past date.');
                        }
                    } elseif ($option === 'next_few_days') {
                        if ($date->lt($tomorrow) || $date->gt($day3)) {
                            $fail('The preferred schedule must be between tomorrow and three days from today.');
                        }
                    }
                },
            ],

            'subject' => ['nullable', 'string', 'max:255'],
            'purchase_interest' => ['nullable', 'boolean'],
            'transaction_method' => ['nullable', 'string', 'in:direct_deal,arrange_delivery'],
            'delivery_method' => ['nullable', 'string', 'max:255'],
            'delivery_fee' => ['nullable', 'numeric', 'min:0'],
            'contact_method' => ['nullable', 'string', 'in:in_app_message'],
            'payment_method' => ['required', 'string', 'in:cash,gcash,maya,other'],
            'collection_method' => [
                'required',
                'string',
                Rule::in([
                    ...InquiryCollectionMethod::selectableValues(),
                    InquiryCollectionMethod::DiscussWithSeller->value,
                ]),
            ],

            'buyer_id' => ['prohibited'],
            'seller_id' => ['prohibited'],
            'status' => ['prohibited'],
            'quantity' => ['prohibited'],
        ];
    }
}
