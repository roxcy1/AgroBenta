<?php

namespace App\Services;

use App\Models\User;
use App\Repositories\UserRepository;
use Illuminate\Support\Facades\Hash;

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

    public function __construct(
        private readonly UserRepository $users,
        private readonly AuthService $auth,
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
     * Issue a token scoped to mobile access only. It never carries `admin`.
     */
    private function issueToken(User $user): string
    {
        return $user->createToken(self::TOKEN_NAME, [self::TOKEN_ABILITY])->plainTextToken;
    }
}
