<?php

namespace App\Http\Requests\Notification;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Validates the query string for `GET /api/notifications`.
 *
 * ## Why `type` is an enum-checked string
 *
 * The client's filter chips ("All", "Transactions", "Inquiries", ...) send a
 * single `type` value, and the value must be one of the four categories the
 * server actually stores. A free-form string would let a typo through and
 * silently return an empty list, which reads as "you have no notifications"
 * rather than "your filter is wrong".
 *
 * ## Why `unread` is `boolean`, not `0`/`1`
 *
 * Laravel's `boolean` rule accepts `"0"`, `"1"`, `"true"`, `"false"`, `true`
 * and `false`. A query string always arrives as strings, so the rule is what
 * normalises them. `per_page` uses the same pattern as the marketplace
 * endpoints: default 15, max 50, out-of-range values are rejected rather than
 * silently clamped.
 */
class IndexNotificationRequest extends FormRequest
{
    /** The four categories the mobile filter chips map to. */
    public const TYPES = [
        'transactions',
        'inquiries',
        'listings',
        'system',
    ];

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
            'type' => ['sometimes', 'string', Rule::in(self::TYPES)],
            'unread' => ['sometimes', 'boolean'],
            'per_page' => ['sometimes', 'integer', 'between:1,50'],
            'page' => ['sometimes', 'integer', 'min:1'],
        ];
    }
}