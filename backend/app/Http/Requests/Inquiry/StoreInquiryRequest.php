<?php

namespace App\Http\Requests\Inquiry;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Support\Carbon;
use Illuminate\Validation\Rule;

/**
 * Body for creating a buyer inquiry from the mobile client.
 *
 * The allow-list is exactly the structured preferences the Inquire form
 * collects: `listing_id`, `message`, the two required preferences
 * (`payment_method`, `collection_method`), the collection-date option, and the
 * remaining optional preference columns of the `inquiries` table. `buyer_id`,
 * `seller_id` and `status` are server-owned — the buyer is the token, the
 * seller is `listing.seller_id`, and an inquiry is always created `open` — so
 * they are refused with a 422 rather than silently dropped.
 *
 * `message` carries the design document's 500-character ceiling so the server
 * and the client's character counter agree, and a whitespace-only message is
 * refused rather than stored as a blank inquiry.
 *
 * `payment_method` and `collection_method` are required: the Inquire form
 * collects both before it can be submitted.
 *
 * `collection_date_option` is required and selects one of `specific_date`,
 * `next_few_days` or `this_week`. When `specific_date` is chosen,
 * `preferred_schedule` is required and must not be a past date; the relative
 * options do not require a date.
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
            'collection_date_option' => [
                'required',
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
            'collection_method' => ['required', 'string', 'in:farm_pickup,buyer_arranged_transportation,discuss_with_seller'],

            'buyer_id' => ['prohibited'],
            'seller_id' => ['prohibited'],
            'status' => ['prohibited'],
        ];
    }
}
