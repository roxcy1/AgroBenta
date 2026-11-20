<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * A user's phone-push switches, one per notification category.
 *
 * `user_id` is not fillable: the owner is always the authenticated user,
 * set by `NotificationPreferenceService`.
 */
#[Fillable(['transactions', 'messages', 'listings', 'verification'])]
class NotificationPreference extends Model
{
    /**
     * The switchable categories, in the order the app shows them.
     */
    public const CATEGORIES = ['transactions', 'messages', 'listings', 'verification'];

    /**
     * Each stored notification `type` and the category that controls its push.
     * A type not listed here is always pushed.
     */
    public const CATEGORY_BY_TYPE = [
        'transactions' => 'transactions',
        'inquiry' => 'messages',
        'listing' => 'listings',
        'seller_verification' => 'verification',
    ];

    /**
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'transactions' => 'boolean',
            'messages' => 'boolean',
            'listings' => 'boolean',
            'verification' => 'boolean',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
