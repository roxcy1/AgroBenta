<?php

namespace App\Repositories\Admin;

use App\Models\Activity;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Builder;

class AdminActivityRepository
{
    public function list(
        ?string $search = null,
        ?string $action = null,
        ?string $userId = null,
        ?string $dateFrom = null,
        ?string $dateTo = null,
        int $perPage = 15,
    ): LengthAwarePaginator {
        $query = Activity::query()
            ->with(['user:id,name,email']);

        $this->applySearch($query, $search);
        $this->applyFilters($query, $action, $userId, $dateFrom, $dateTo);

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
            $q->where('action', 'like', $term)
                ->orWhere('description', 'like', $term)
                ->orWhereHas('user', function (Builder $q2) use ($term): void {
                    $q2->where('name', 'like', $term)
                        ->orWhere('email', 'like', $term);
                });
        });
    }

    private function applyFilters(Builder $query, ?string $action, ?string $userId, ?string $dateFrom, ?string $dateTo): void
    {
        if ($action !== null && $action !== '') {
            $query->where('action', $action);
        }

        if ($userId !== null && $userId !== '') {
            $query->where('user_id', $userId);
        }

        if ($dateFrom !== null && $dateFrom !== '') {
            $query->where('created_at', '>=', $dateFrom);
        }

        if ($dateTo !== null && $dateTo !== '') {
            $query->where('created_at', '<=', $dateTo.' 23:59:59');
        }
    }
}
