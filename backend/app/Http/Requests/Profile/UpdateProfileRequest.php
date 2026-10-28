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
 * address. `role`, `seller_capability`, `password` and `id` are prohibited
 * from profile updates. Changing email requires the current password.
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
        $user = $this->user();

        $rules = [
            'role' => ['prohibited'],
            'seller_capability' => ['prohibited'],
            'id' => ['prohibited'],
            'password' => ['prohibited'],
            'name' => ['sometimes', 'string', 'min:2', 'max:120'],
            'email' => [
                'sometimes',
                'string',
                'email:rfc',
                'max:191',
                Rule::unique('users', 'email')->ignore($user->id),
            ],
            'phone' => ['sometimes', 'nullable', 'string', 'max:32'],
            'location' => ['sometimes', 'nullable', 'string', 'max:191'],
            'avatar_url' => ['sometimes', 'nullable', 'url', 'max:2048'],
            'bio' => ['sometimes', 'nullable', 'string', 'max:1000'],
        ];

        if ($this->filled('email') && $this->input('email') !== $user->email) {
            $rules['current_password'] = ['required', 'current_password'];
        } elseif ($this->has('current_password')) {
            $rules['current_password'] = ['sometimes', 'current_password'];
        }

        return $rules;
    }
}