<?php

namespace App\Http\Requests\Device;

use Illuminate\Foundation\Http\FormRequest;

/**
 * POST /api/devices — register the phone's FCM token.
 *
 * The token is the only field. The owner is the authenticated user, so a
 * `user_id` is refused rather than ignored.
 */
class StoreDeviceTokenRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, array<int, string>>
     */
    public function rules(): array
    {
        return [
            'token' => ['required', 'string', 'max:512'],
            'user_id' => ['prohibited'],
        ];
    }
}
