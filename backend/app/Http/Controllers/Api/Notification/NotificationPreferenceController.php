<?php

namespace App\Http\Controllers\Api\Notification;

use App\Http\Controllers\Controller;
use App\Http\Requests\Notification\UpdateNotificationPreferencesRequest;
use App\Services\Notification\NotificationPreferenceService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The caller's own push switches (Profile → Notification Settings).
 *
 * Resolved from the token; no route takes a user id. `data` is always the full
 * set: `transactions`, `messages`, `listings`, `verification`, each a boolean.
 */
class NotificationPreferenceController extends Controller
{
    public function __construct(private readonly NotificationPreferenceService $preferences)
    {
    }

    /**
     * GET /api/notification-preferences
     */
    public function show(Request $request): JsonResponse
    {
        return response()->json([
            'success' => true,
            'message' => 'Notification settings retrieved.',
            'data' => $this->preferences->forUser($request->user()),
        ]);
    }

    /**
     * PUT /api/notification-preferences
     */
    public function update(UpdateNotificationPreferencesRequest $request): JsonResponse
    {
        $changes = array_map('boolval', $request->validated());

        return response()->json([
            'success' => true,
            'message' => 'Notification settings saved.',
            'data' => $this->preferences->update($request->user(), $changes),
        ]);
    }
}
