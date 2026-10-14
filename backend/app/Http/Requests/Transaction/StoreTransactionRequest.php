<?php

namespace App\Http\Requests\Transaction;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Body for creating a transaction.
 *
 * The allow-list is exactly `{ listing_id, quantity }`. The caller is the
 * buyer ([D-15] rule 1); `buyer_id`, `seller_id`, `total_amount` and `status`
 * are server-derived and rejected with a 422 rather than silently dropped —
 * dropping them would hide a client bug, honouring them would let a buyer
 * set their own price or counterparty.
 */
class StoreTransactionRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, list<string>>
     */
    public function rules(): array
    {
        return [
            'listing_id' => ['required', 'integer', 'exists:listings,id'],
            'quantity' => ['required', 'integer', 'min:1'],

            'buyer_id' => ['prohibited'],
            'seller_id' => ['prohibited'],
            'total_amount' => ['prohibited'],
            'status' => ['prohibited'],
        ];
    }
}
