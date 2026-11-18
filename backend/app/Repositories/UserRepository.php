<?php

namespace App\Repositories;

use App\Enums\SellerCapability;
use App\Enums\UserRole;
use App\Models\User;

class UserRepository
{
    /**
     * Find a user by their email address.
     */
    public function findByEmail(string $email): ?User
    {
        return User::query()->where('email', $email)->first();
    }

    /**
     * Create a normal user.
     *
     * `$attributes` carries only the caller-supplied, already validated
     * profile fields. The authority fields are derived here and are never
     * accepted from the caller: a new account is always `role=user` and
     * `seller_capability=buyer`. They are not mass assignable on the model,
     * so they are set explicitly via `forceFill` from this trusted path.
     * Granting seller capability is the seller verification workflow's job.
     *
     * @param  array<string, mixed>  $attributes
     */
    public function create(array $attributes): User
    {
        $user = new User;

        $user->fill($attributes);

        $user->forceFill([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $user->save();

        return $user;
    }

    /**
     * Read [id] under a row lock for an avatar replacement.
     *
     * Used inside the avatar upload transaction so the previous URL is read
     * from the committed row rather than from the request-scoped model. Two
     * overlapping uploads therefore serialize, and the second one replaces the
     * first one's URL instead of a stale one.
     */
    public function findForUpdate(int $id): ?User
    {
        return User::query()->whereKey($id)->lockForUpdate()->first();
    }

    /**
     * Persist a new avatar URL for [user].
     *
     * Only `avatar_url` is written. The caller has already decided which file
     * the URL points at; ownership of that file is enforced by the avatar
     * service before this runs.
     */
    public function updateAvatarUrl(User $user, string $url): User
    {
        $user->avatar_url = $url;
        $user->save();

        return $user;
    }
}
