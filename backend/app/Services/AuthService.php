<?php

namespace App\Services;

use App\Models\User;
use App\Repositories\UserRepository;
use Illuminate\Support\Facades\Hash;

class AuthService
{
    public function __construct(private readonly UserRepository $users)
    {
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

        return [
            'user' => $user,
            'token' => $user->createToken('admin_token', ['admin'])->plainTextToken,
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
