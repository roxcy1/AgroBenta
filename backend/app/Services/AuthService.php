<?php

namespace App\Services;

use App\Enums\ActivityAction;
use App\Models\User;
use App\Repositories\UserRepository;
use Illuminate\Support\Facades\Hash;

class AuthService
{
    public function __construct(
        private readonly UserRepository $users,
        private readonly ActivityLogger $activity,
    ) {
        //
    }

    /**
     * Attempt an administrator login and issue a Sanctum bearer token.
     *
     * Returns the authenticated user and plain-text token, or null when the
     * credentials are invalid or the account does not hold admin access.
     *
     * @return array{user: User, token: string}|null
     */
    public function login(string $email, string $password): ?array
    {
        $user = $this->users->findByEmail($email);

        if ($user === null || ! Hash::check($password, $user->password) || ! $user->isAdmin()) {
            return null;
        }

        $token = $user->createToken('admin_token', ['admin']);

        // Best-effort: a login that succeeds but cannot be audited must still
        // hand the administrator their token, so the failure is swallowed.
        $this->activity->logSafely(
            $user,
            ActivityAction::AdminLoggedIn,
            'Administrator signed in.',
            ['context' => ['guard' => 'admin']],
        );

        return [
            'user' => $user,
            'token' => $token->plainTextToken,
        ];
    }

    /**
     * Revoke the caller's current bearer token.
     */
    public function logout(User $user): void
    {
        $user->currentAccessToken()?->delete();
    }
}
