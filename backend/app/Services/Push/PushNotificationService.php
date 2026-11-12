<?php

namespace App\Services\Push;

use App\Models\DeviceToken;
use App\Models\User;
use Illuminate\Http\Client\Response;
use Illuminate\Support\Facades\Http;
use Laravel\Sanctum\PersonalAccessToken;
use RuntimeException;
use Throwable;

/**
 * Phone push notifications through Firebase Cloud Messaging (HTTP v1 API).
 *
 * A push is only a pointer to a notification already stored in the database:
 * the notification's title, a fixed body, and the ids the app needs to open
 * it. Free text that can appear in a stored body (an administrator's note, a
 * buyer's name) stays in the app and never reaches the lock screen.
 */
class PushNotificationService
{
    public const BODY = 'Open AgroBenta to see the details.';

    /** FCM error codes that mean the registration token will never work again. */
    private const STALE_TOKEN_ERRORS = ['UNREGISTERED', 'SENDER_ID_MISMATCH'];

    public function __construct(
        private readonly FcmCredentials $credentials,
    ) {}

    public function isEnabled(): bool
    {
        return $this->credentials->isConfigured();
    }

    /**
     * Register the calling phone for the session that is signed in on it.
     *
     * An upsert on the unique token, so a phone that signs in to another
     * account moves to that account, and two concurrent calls cannot collide.
     */
    public function registerDevice(User $user, PersonalAccessToken $accessToken, string $token): void
    {
        $now = now();

        DeviceToken::query()->upsert(
            [[
                'user_id' => $user->getKey(),
                'personal_access_token_id' => $accessToken->getKey(),
                'token' => $token,
                'created_at' => $now,
                'updated_at' => $now,
            ]],
            ['token'],
            ['user_id', 'personal_access_token_id', 'updated_at'],
        );
    }

    /**
     * Send one push to every phone the user has registered.
     *
     * Each phone is sent separately, so one failure never stops the others.
     * A token FCM reports as gone is deleted. Failures are reported without the
     * device token, the access token or the response body.
     *
     * @param  array<string, string>  $data
     */
    public function sendToUser(int $userId, string $title, array $data): void
    {
        $devices = DeviceToken::query()->where('user_id', $userId)->get(['id', 'token']);

        if ($devices->isEmpty() || ! $this->isEnabled()) {
            return;
        }

        $url = 'https://fcm.googleapis.com/v1/projects/'.$this->credentials->projectId().'/messages:send';

        foreach ($devices as $device) {
            try {
                $response = Http::withToken($this->credentials->accessToken())
                    ->connectTimeout(3)
                    ->timeout(10)
                    ->post($url, ['message' => [
                        'token' => $device->token,
                        'notification' => ['title' => $title, 'body' => self::BODY],
                        'data' => $data,
                        'android' => ['priority' => 'high'],
                    ]]);
            } catch (Throwable $exception) {
                report(new RuntimeException('FCM send request failed ('.$exception::class.').'));

                continue;
            }

            if ($response->successful()) {
                continue;
            }

            if ($this->isStaleToken($response)) {
                $device->delete();

                continue;
            }

            if ($response->status() === 401) {
                $this->credentials->forgetAccessToken();
            }

            report(new RuntimeException("FCM send failed with HTTP {$response->status()}."));
        }
    }

    private function isStaleToken(Response $response): bool
    {
        if ($response->status() === 404) {
            return true;
        }

        foreach ((array) $response->json('error.details', []) as $detail) {
            if (is_array($detail) && in_array($detail['errorCode'] ?? null, self::STALE_TOKEN_ERRORS, true)) {
                return true;
            }
        }

        return false;
    }
}
