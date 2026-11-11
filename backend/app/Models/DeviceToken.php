<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\Hidden;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * A phone's Firebase Cloud Messaging registration token.
 *
 * Tied to the Sanctum access token of the session that registered it; see the
 * `create_device_tokens_table` migration for the lifecycle.
 */
#[Fillable(['user_id', 'personal_access_token_id', 'token'])]
#[Hidden(['token'])]
class DeviceToken extends Model
{
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
