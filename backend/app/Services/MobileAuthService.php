<?php

namespace App\Services;

use App\Enums\ActivityAction;
use App\Enums\UserRole;
use App\Models\User;
use App\Repositories\UserRepository;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Password;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Str;
use Throwable;

/**
 * Mobile authentication.
 *
 * Deliberately separate from the Admin Web flow in {@see AuthService}. That
 * service hard-requires `isAdmin()` and issues a token carrying the `admin`
 * ability; reusing it here would hand every mobile user administrator
 * authority. Mobile issues its own token scoped to `mobile` only.
 */
class MobileAuthService
{
    /**
     * The token name and ability issued to mobile clients.
     */
    public const TOKEN_NAME = 'mobile';

    public const TOKEN_ABILITY = 'mobile';

    public const RESULT_AUTHENTICATED = 'authenticated';

    public const RESULT_INVALID_CREDENTIALS = 'invalid_credentials';

    public const RESULT_NOT_PERMITTED = 'not_permitted';

    /**
     * Wrong reset codes allowed per email before attempts are refused. The
     * route throttle is per IP, so this is what limits guessing across many
     * addresses at one account's code.
     */
    public const MAX_RESET_CODE_ATTEMPTS = 5;

    public function __construct(
        private readonly UserRepository $users,
        private readonly AuthService $auth,
        private readonly ActivityLogger $activity,
        private readonly GoogleIdTokenVerifier $google,
    ) {
        //
    }

    /**
     * Register a normal user and issue a mobile-scoped bearer token.
     *
     * `role` and `seller_capability` are derived by the repository, so a
     * request that supplies them cannot influence the created account.
     *
     * @param  array{name: string, email: string, password: string}  $attributes
     * @return array{user: User, token: string}
     */
    public function register(array $attributes): array
    {
        $user = $this->users->create($attributes);

        return [
            'user' => $user,
            'token' => $this->issueToken($user),
        ];
    }

    /**
     * Attempt a mobile login and issue a mobile-scoped bearer token.
     *
     * Returns a result discriminator rather than throwing, so the controller
     * owns the HTTP mapping. The admin check runs only after the password has
     * been proven, so a 403 cannot be used to enumerate accounts.
     *
     * @return array{result: string, user?: User, token?: string}
     */
    public function login(string $email, string $password): array
    {
        $user = $this->users->findByEmail($email);

        // One generic outcome, never distinguishing "no such user" from
        // "wrong password".
        if ($user === null || ! Hash::check($password, $user->password)) {
            return ['result' => self::RESULT_INVALID_CREDENTIALS];
        }

        if ($user->isAdmin()) {
            return ['result' => self::RESULT_NOT_PERMITTED];
        }

        // Best-effort: an unauditable login still issues its token, and this is
        // deliberately not wired into `register` — account creation is not a
        // sign-in.
        $this->activity->logSafely(
            $user,
            ActivityAction::UserLoggedIn,
            'User signed in.',
            ['context' => ['guard' => 'mobile']],
        );

        return [
            'result' => self::RESULT_AUTHENTICATED,
            'user' => $user,
            'token' => $this->issueToken($user),
        ];
    }

    /**
     * Sign in with a Google ID token and issue a mobile-scoped bearer token.
     *
     * Project decision (MS-11, 2026-11-10): an existing account with the same
     * email is signed in, since Google has verified that email; an unknown
     * email gets a new normal user account. A new account receives a random
     * password nobody knows; Forgot Password can set a real one later.
     *
     * @return array{result: string, user?: User, token?: string}
     */
    public function loginWithGoogle(string $idToken): array
    {
        $identity = $this->google->verify($idToken);

        if ($identity === null) {
            return ['result' => self::RESULT_INVALID_CREDENTIALS];
        }

        $user = $this->users->findByEmail($identity['email']);

        // Administrators never use the mobile app, and a deleted account's
        // email still holds its unique slot, so neither gets a new account.
        if ($user?->isAdmin()
            || ($user === null && User::onlyTrashed()->where('email', $identity['email'])->exists())) {
            return ['result' => self::RESULT_NOT_PERMITTED];
        }

        $user ??= $this->users->create([
            'name' => $identity['name'] ?? Str::before($identity['email'], '@'),
            'email' => $identity['email'],
            'password' => Str::random(64),
        ]);

        $this->activity->logSafely(
            $user,
            ActivityAction::UserLoggedIn,
            'User signed in.',
            ['context' => ['guard' => 'mobile', 'method' => 'google']],
        );

        return [
            'result' => self::RESULT_AUTHENTICATED,
            'user' => $user,
            'token' => $this->issueToken($user),
        ];
    }

    /**
     * Revoke the caller's current mobile bearer token.
     */
    public function logout(User $user): void
    {
        $this->auth->logout($user);
    }

    /**
     * Email a password reset code, when the address belongs to a mobile user.
     *
     * Returns nothing, so no outcome can reach the response: an unknown email,
     * an administrator, a repeat within the broker's throttle and a mail failure
     * all look the same to the caller. A failure is reported to the log only,
     * because it can happen only for a real account.
     */
    public function sendPasswordResetCode(string $email): void
    {
        try {
            Password::sendResetLink($this->resetCredentials($email));
        } catch (Throwable $exception) {
            report($exception);
        }
    }

    /**
     * Set a new password from a reset code and revoke every existing token.
     *
     * Returns false for a wrong or expired code, an unknown email, and an email
     * that has run out of attempts, without saying which. The attempt counter
     * outlives any one code, so requesting new codes does not grant new guesses.
     */
    public function resetPassword(string $email, string $code, string $password): bool
    {
        $attemptsKey = 'password-reset-code:'.sha1(Str::lower($email));

        if (RateLimiter::tooManyAttempts($attemptsKey, self::MAX_RESET_CODE_ATTEMPTS)) {
            return false;
        }

        // Counted before the check, so parallel requests cannot share a guess.
        $broker = config('auth.defaults.passwords');
        RateLimiter::hit($attemptsKey, config("auth.passwords.{$broker}.expire") * 60);

        $status = Password::reset(
            [...$this->resetCredentials($email), 'token' => $code, 'password' => $password],
            function (User $user, string $password): void {
                $user->forceFill(['password' => $password])->save();
                $user->tokens()->delete();
            },
        );

        if ($status !== Password::PASSWORD_RESET) {
            return false;
        }

        RateLimiter::clear($attemptsKey);

        return true;
    }

    /**
     * Limit the broker's user lookup to mobile users. Administrators cannot use
     * the mobile app, so a six-digit code must not be able to reset their
     * passwords, and they get the same outcome as an unknown email.
     *
     * @return array{email: string, role: string}
     */
    private function resetCredentials(string $email): array
    {
        return ['email' => $email, 'role' => UserRole::User->value];
    }

    /**
     * Issue a token scoped to mobile access only. It never carries `admin`.
     */
    private function issueToken(User $user): string
    {
        return $user->createToken(self::TOKEN_NAME, [self::TOKEN_ABILITY])->plainTextToken;
    }
}
