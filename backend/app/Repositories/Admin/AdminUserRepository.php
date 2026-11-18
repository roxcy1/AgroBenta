<?php

namespace App\Repositories\Admin;

use App\Enums\SellerCapability;
use App\Enums\TransactionStatus;
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

    public function findTrashedForUpdate(int $id): ?User
    {
        return User::withTrashed()
            ->whereKey($id)
            ->lockForUpdate()
            ->first();
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

    /** Persist the administrative reason and actor before the soft delete. */
    public function markDeactivated(User $user, User $actor, string $reason): void
    {
        $user->deactivation_reason = $reason;
        $user->deactivated_by = $actor->getKey();
        $user->save();
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

    public function restore(User $user): void
    {
        $user->restore();
    }

    /**
     * Load the aggregate fields the admin user projection needs.
     */
    public function loadMetrics(User $user): User
    {
        return $user
            ->loadCount($this->metricCounts())
            ->loadMissing('deactivatedBy:id,name');
    }

    public function list(
        ?string $search = null,
        ?string $role = null,
        ?string $sellerCapability = null,
        ?string $status = null,
        int $perPage = 15,
    ): LengthAwarePaginator {
        $query = match ($status) {
            'deactivated' => User::onlyTrashed(),
            'all' => User::withTrashed(),
            default => User::query(),
        };

        $query
            ->withCount($this->metricCounts())
            ->with('deactivatedBy:id,name');

        $this->applySearch($query, $search);
        $this->applyFilters($query, $role, $sellerCapability);

        return $query
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->paginate($perPage);
    }

    /**
     * @return array<string, mixed>
     */
    private function metricCounts(): array
    {
        return [
            'receivedReports as reports_count',
            'transactionsAsBuyer as pending_buyer_transactions_count' => fn (Builder $query): Builder => $query
                ->where('status', TransactionStatus::Pending),
            'transactionsAsSeller as pending_seller_transactions_count' => fn (Builder $query): Builder => $query
                ->where('status', TransactionStatus::Pending),
        ];
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
