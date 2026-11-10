<?php

namespace App\Repositories\Admin;

use App\Enums\SellerCapability;
use App\Enums\UserRole;
use App\Models\User;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\DB;

class AdminUserRepository
{
    public function findForUpdate(int $id): ?User
    {
        return User::query()->whereKey($id)->lockForUpdate()->first();
    }

    /**
     * Lock active administrator rows in a stable order for last-admin checks.
     *
     * @return Collection<int, User>
     */
    public function lockActiveAdministrators(): Collection
    {
        return User::query()
            ->where('role', UserRole::Admin)
            ->orderBy('id')
            ->lockForUpdate()
            ->get(['id', 'role']);
    }

    /** @param array{name: string, email: string} $attributes */
    public function update(User $user, array $attributes): User
    {
        $user->name = $attributes['name'];
        $user->email = $attributes['email'];
        $user->save();

        return $user->refresh();
    }

    /** Revoke all API and database-session credentials before deactivation. */
    public function revokeCredentials(User $user): void
    {
        $user->tokens()->delete();

        DB::table('sessions')->where('user_id', $user->getKey())->delete();
        DB::table('password_reset_tokens')->where('email', $user->email)->delete();
    }

    public function softDelete(User $user): void
    {
        $user->delete();
    }

    public function list(
        ?string $search = null,
        ?string $role = null,
        ?string $sellerCapability = null,
        int $perPage = 15,
    ): LengthAwarePaginator {
        $query = User::query();

        $this->applySearch($query, $search);
        $this->applyFilters($query, $role, $sellerCapability);

        return $query
            ->orderByDesc('created_at')
            ->paginate($perPage);
    }

    private function applySearch(Builder $query, ?string $search): void
    {
        if ($search === null || $search === '') {
            return;
        }

        $term = '%'.$search.'%';

        $query->where(function (Builder $q) use ($term): void {
            $q->where('name', 'like', $term)
                ->orWhere('email', 'like', $term);
        });
    }

    private function applyFilters(Builder $query, ?string $role, ?string $sellerCapability): void
    {
        if ($role !== null && $role !== '') {
            $query->where('role', UserRole::from($role));
        }

        if ($sellerCapability !== null && $sellerCapability !== '') {
            $query->where('seller_capability', SellerCapability::from($sellerCapability));
        }
    }
}
