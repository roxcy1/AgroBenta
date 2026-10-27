<?php

namespace App\Http\Requests\Profile;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Validates a profile update.
 *
 * Every field is `sometimes`-guarded so a PATCH-shaped update that sends only
 * `phone` does not blank the other columns. The client sends only what changed.
 *
 * `email` is deliberately included — a user may correct a typo in their own
 * address — but `role`, `seller_capability`, `password` and `id` are not, and
 * are not fillable on the model, so no request can reach them.
 */
class UpdateProfileRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user() !== null;
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'name' => ['sometimes', 'string', 'min:2', 'max:120'],
            'email' => [
                'sometimes',
                'string',
                'email:rfc',
                'max:191',
                Rule::unique('users', 'email')->ignore($this->user()->id),
            ],
            'phone' => ['sometimes', 'nullable', 'string', 'max:32'],
            'location' => ['sometimes', 'nullable', 'string', 'max:191'],
            'avatar_url' => ['sometimes', 'nullable', 'url', 'max:2048'],
            'bio' => ['sometimes', 'nullable', 'string', 'max:1000'],
        ];
    }
}