<?php

namespace App\Services\Push;

use Google\Auth\Credentials\ServiceAccountCredentials;
use Illuminate\Support\Facades\Cache;
use RuntimeException;

/**
 * The Firebase service account used to send push notifications.
 *
 * Reads the JSON key named by `services.fcm.credentials` and exchanges it for
 * a short-lived OAuth access token with Google's official auth library. The
 * access token is cached until shortly before it expires. The key itself is
 * never logged or returned.
 */
class FcmCredentials
{
    private const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

    private const CACHE_KEY = 'fcm.access_token';

    /** @var array<string, mixed>|null */
    private ?array $key = null;

    /**
     * Push is on only when a key path is configured.
     */
    public function isConfigured(): bool
    {
        $path = config('services.fcm.credentials');

        return is_string($path) && trim($path) !== '';
    }

    public function projectId(): string
    {
        $projectId = $this->key()['project_id'] ?? null;

        if (! is_string($projectId) || $projectId === '') {
            throw new RuntimeException('The Firebase service account key has no project_id.');
        }

        return $projectId;
    }

    public function accessToken(): string
    {
        $cached = Cache::get(self::CACHE_KEY);

        if (is_string($cached) && $cached !== '') {
            return $cached;
        }

        $result = (new ServiceAccountCredentials(self::SCOPE, $this->key()))->fetchAuthToken();
        $token = $result['access_token'] ?? null;

        if (! is_string($token) || $token === '') {
            throw new RuntimeException('Google did not return a Firebase access token.');
        }

        $lifetime = (int) ($result['expires_in'] ?? 3600);
        Cache::put(self::CACHE_KEY, $token, max(60, $lifetime - 300));

        return $token;
    }

    /**
     * Drop the cached access token, after FCM refused it.
     */
    public function forgetAccessToken(): void
    {
        Cache::forget(self::CACHE_KEY);
    }

    /**
     * @return array<string, mixed>
     */
    private function key(): array
    {
        if ($this->key !== null) {
            return $this->key;
        }

        $path = (string) config('services.fcm.credentials');

        if (! str_starts_with($path, '/') && preg_match('/^[A-Za-z]:[\\\\\/]/', $path) !== 1) {
            $path = base_path($path);
        }

        $contents = is_file($path) ? file_get_contents($path) : false;
        $key = $contents === false ? null : json_decode($contents, true);

        if (! is_array($key)) {
            // The path is configuration, not a secret, but the message stays
            // generic so a misconfiguration never echoes file contents.
            throw new RuntimeException('The Firebase service account key named by FCM_CREDENTIALS cannot be read.');
        }

        return $this->key = $key;
    }
}
