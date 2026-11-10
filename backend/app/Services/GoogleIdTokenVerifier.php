<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use Throwable;

/**
 * Verifies a Google Sign-In ID token sent by the mobile app.
 *
 * Google's `tokeninfo` endpoint checks the token's signature and expiry; this
 * class then checks that the token was issued by Google, for this app's server
 * client ID, with a verified email. No client secret is involved.
 */
class GoogleIdTokenVerifier
{
    private const TOKENINFO_URL = 'https://oauth2.googleapis.com/tokeninfo';

    private const ISSUERS = ['accounts.google.com', 'https://accounts.google.com'];

    /**
     * Return the token's identity, or null when the token is not acceptable.
     *
     * @return array{sub: string, email: string, name: string|null}|null
     */
    public function verify(string $idToken): ?array
    {
        $clientId = config('services.google.client_id');

        if (! is_string($clientId) || $clientId === '') {
            report(new \RuntimeException('GOOGLE_CLIENT_ID is not configured.'));

            return null;
        }

        try {
            $response = Http::connectTimeout(3)
                ->timeout(5)
                ->get(self::TOKENINFO_URL, ['id_token' => $idToken]);
        } catch (Throwable $exception) {
            report($exception);

            return null;
        }

        if (! $response->successful()) {
            return null;
        }

        $claims = $response->json();

        if (! is_array($claims)
            || ($claims['aud'] ?? null) !== $clientId
            || ! in_array($claims['iss'] ?? null, self::ISSUERS, true)
            || (string) ($claims['email_verified'] ?? '') !== 'true'
            || (int) ($claims['exp'] ?? 0) <= time()
            || ! is_string($claims['sub'] ?? null)
            || ! is_string($claims['email'] ?? null)
            || filter_var($claims['email'], FILTER_VALIDATE_EMAIL) === false) {
            return null;
        }

        $name = $claims['name'] ?? null;

        return [
            'sub' => $claims['sub'],
            'email' => $claims['email'],
            'name' => is_string($name) && trim($name) !== '' ? trim($name) : null,
        ];
    }
}
