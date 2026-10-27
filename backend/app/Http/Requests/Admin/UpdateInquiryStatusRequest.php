<?php

namespace App\Http\Requests\Admin;

use Illuminate\Foundation\Http\FormRequest;

/**
 * The only field an administrator may change on an inquiry is its workflow
 * status. The buyer's original message and stated preferences are immutable:
 * they are a record of what the buyer asked, not editable content.
 */
class UpdateInquiryStatusRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'status' => ['required', 'string', 'in:open,responded,closed'],
        ];
    }
}
