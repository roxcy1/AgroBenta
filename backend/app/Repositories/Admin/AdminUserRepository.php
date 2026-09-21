<?php

namespace App\Repositories\Admin;

use App\Enums\SellerCapability;
use App\Enums\UserRole;
use App\Models\User;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Builder;

class AdminUserRepository
{
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
