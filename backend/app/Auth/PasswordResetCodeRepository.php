<?php

namespace App\Auth;

use App\Services\MobileAuthService;
use Illuminate\Auth\Passwords\DatabaseTokenRepository;

/**
 * Issues a six-digit code instead of Laravel's 64-character reset token, so a
 * user can type it into the mobile app (MS-10).
 *
 * Storage, hashing, expiry, single use and the per-email resend throttle are all
 * inherited unchanged. A code is far easier to guess than the default token, so
 * every wrong attempt is counted in {@see MobileAuthService}.
 */
class PasswordResetCodeRepository extends DatabaseTokenRepository
{
    /**
     * @return string
     */
    public function createNewToken()
    {
        return str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);
    }
}
