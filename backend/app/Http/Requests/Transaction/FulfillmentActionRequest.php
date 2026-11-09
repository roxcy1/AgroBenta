<?php

namespace App\Http\Requests\Transaction;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Body for a fulfillment action, which takes no input.
 *
 * Every present key is `prohibited`, so a future column is rejected the day it
 * appears rather than silently ignored. The same pattern is used by
 * `CancelTransactionRequest` and the seller listing action requests.
 */
class FulfillmentActionRequest extends FormRequest
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
