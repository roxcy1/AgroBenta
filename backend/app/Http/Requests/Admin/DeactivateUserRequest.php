<?php

namespace App\Http\Requests\Admin;

use Illuminate\Foundation\Http\FormRequest;

class DeactivateUserRequest extends FormRequest
{
    protected function prepareForValidation(): void
    {
        $this->merge([
            'reason' => is_string($this->input('reason'))
                ? trim($this->input('reason'))
                : $this->input('reason'),
        ]);
    }

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
            'reason' => ['required', 'string', 'min:5', 'max:1000', 'not_regex:/^\s*$/'],

            'id' => ['prohibited'],
            'role' => ['prohibited'],
            'seller_capability' => ['prohibited'],
            'status' => ['prohibited'],
            'deactivation_reason' => ['prohibited'],
            'deactivated_by' => ['prohibited'],
            'deleted_at' => ['prohibited'],
        ];
    }
}
