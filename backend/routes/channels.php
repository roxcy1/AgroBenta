<?php

use App\Models\User;
use Illuminate\Support\Facades\Broadcast;

/*
|--------------------------------------------------------------------------
| Broadcast Channels
|--------------------------------------------------------------------------
|
| Register the authorization callbacks for private channels. The `$user`
| argument is the authenticated user (resolved by `auth:sanctum` on the
| `/broadcasting/auth` endpoint); the callback returns whether that user may
| subscribe to the channel named by the other arguments.
|
| Channels are per-user. A client subscribes only to its own `user.{id}`
| (or, for the Admin Web, its own `admin.{id}`) channel, so the rule is a
| single self-check — never trust a client-supplied id.
|
*/

Broadcast::channel('user.{id}', function (User $user, int $id) {
    return (int) $user->getKey() === (int) $id;
});

Broadcast::channel('admin.{id}', function (User $user, int $id) {
    return $user->isAdmin() && (int) $user->getKey() === (int) $id;
});

// A shared feed for every administrator (the dashboard/activity/moderation
// surfaces). Membership is decided by the server-side `isAdmin()` capability,
// never by a client value.
Broadcast::channel('admin', function (User $user) {
    return $user->isAdmin();
});
