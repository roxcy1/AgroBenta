<?php

namespace App\Repositories\Marketplace;

use App\Models\User;

/**
 * Data access for the public seller profile.
 *
 * A public seller is an ordinary account whose profile a marketplace reader may
 * view. This repository deliberately selects only the fields the public
 * projection needs — never the email address, phone number or raw address — so
 * a later resource change cannot make a private column reachable by accident.
 *
 * `User` uses `SoftDeletes`, and the model's global scope excludes trashed
 * accounts, so a removed seller is indistinguishable from an unknown id: both
 * resolve to null and the controller answers the same 404.
 */
class MarketplaceSellerRepository
{
    /**
     * Find one non-deleted account by id, with the public profile columns.
     */
    public function findPublicSeller(int $sellerId): ?User
    {
        return User::query()
            ->select([
                'id',
                'name',
                'avatar_url',
                'bio',
                'location',
                'created_at',
                'seller_capability',
                'deleted_at',
            ])
            ->whereKey($sellerId)
            ->first();
    }
}
