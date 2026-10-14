<?php

namespace App\Http\Requests\Transaction;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Body for the cancel action, which takes no input.
 *
 * An empty allow-list enforced explicitly: Laravel ignores a key that
 * appears in no rule, so a literally empty `rules()` would silently drop
 * every field. Every present key is `prohibited`, so a future column is
 * rejected the day it appears (same pattern as
 * `SellerListingActionRequest`).
 */
class CancelTransactionRequest extends FormRequest
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
        return array_fill_keys(
            array_keys($this->all()),
            ['prohibited'],
        );
    }
}
