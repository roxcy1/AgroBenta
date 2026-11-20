<?php

namespace App\Http\Requests\Notification;

use Illuminate\Foundation\Http\FormRequest;

/**
 * PUT /api/notification-preferences — switch push categories on or off.
 *
 * Partial: send only the switches that change, at least one. The owner is the
 * authenticated user, so a `user_id` is refused rather than ignored.
 */
class UpdateNotificationPreferencesRequest extends FormRequest
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
        $atLeastOne = 'required_without_all:transactions,messages,listings,verification';

        return [
            'transactions' => [$atLeastOne, 'boolean'],
            'messages' => [$atLeastOne, 'boolean'],
            'listings' => [$atLeastOne, 'boolean'],
            'verification' => [$atLeastOne, 'boolean'],
            'user_id' => ['prohibited'],
        ];
    }
}
