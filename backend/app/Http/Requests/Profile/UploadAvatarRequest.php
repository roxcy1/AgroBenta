<?php

namespace App\Http\Requests\Profile;

use Illuminate\Foundation\Http\FormRequest;

/**
 * A single avatar upload for the authenticated account.
 *
 * There is no path parameter: the target file always belongs to the caller, so
 * the request can never be pointed at another user's avatar.
 */
class UploadAvatarRequest extends FormRequest
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
            // 5 MB ceiling; the extension allow-list is checked against the
            // detected MIME type, not the client-supplied file name.
            'avatar' => ['required', 'image', 'mimes:jpg,jpeg,png,webp', 'max:5120'],
        ];
    }
}
