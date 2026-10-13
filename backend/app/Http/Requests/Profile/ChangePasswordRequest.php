<?php

namespace App\Http\Requests\Profile;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rules\Password;

/**
 * Validates a password change.
 *
 * `current_password` is validated against the authenticated user's stored hash
 * by Laravel's built-in rule, so a wrong current password is a 422 rather than
 * a 403 — the user is authenticated, they just typed the wrong thing.
 */
class ChangePasswordRequest extends FormRequest
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
            'current_password' => ['required', 'current_password'],
            'password' => ['required', 'confirmed', Password::min(8)],
        ];
    }
}