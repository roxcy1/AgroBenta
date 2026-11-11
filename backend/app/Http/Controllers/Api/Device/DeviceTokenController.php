<?php

namespace App\Http\Controllers\Api\Device;

use App\Http\Controllers\Controller;
use App\Http\Requests\Device\StoreDeviceTokenRequest;
use App\Services\Push\PushNotificationService;
use Illuminate\Http\JsonResponse;
use Laravel\Sanctum\PersonalAccessToken;

/**
 * The calling phone's push registration.
 *
 * There is no unregister route: the registration belongs to the session's
 * access token and is deleted with it on logout.
 */
class DeviceTokenController extends Controller
{
    public function __construct(
        private readonly PushNotificationService $push,
    ) {}

    /**
     * POST /api/devices
     */
    public function store(StoreDeviceTokenRequest $request): JsonResponse
    {
        $user = $request->user();
        $accessToken = $user->currentAccessToken();

        if (! $accessToken instanceof PersonalAccessToken) {
            return response()->json([
                'success' => false,
                'message' => 'A mobile access token is required.',
            ], 401);
        }

        $this->push->registerDevice($user, $accessToken, (string) $request->validated('token'));

        return response()->json([
            'success' => true,
            'message' => 'Device registered for notifications.',
        ]);
    }
}
