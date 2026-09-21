<?php

namespace App\Repositories\Admin;

use App\Enums\TransactionStatus;
use App\Models\Transaction;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Builder;

class AdminTransactionRepository
{
    public function list(
        ?string $search = null,
        ?string $status = null,
        ?string $dateFrom = null,
        ?string $dateTo = null,
        int $perPage = 15,
    ): LengthAwarePaginator {
        $query = Transaction::query()
            ->with(['buyer:id,name,email', 'seller:id,name,email', 'listing:id,livestock_type,breed']);

        $this->applySearch($query, $search);
        $this->applyFilters($query, $status, $dateFrom, $dateTo);

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
            $q->where('id', 'like', $term)
                ->orWhereHas('buyer', function (Builder $q2) use ($term): void {
                    $q2->where('name', 'like', $term)
                        ->orWhere('email', 'like', $term);
                })
                ->orWhereHas('seller', function (Builder $q2) use ($term): void {
                    $q2->where('name', 'like', $term)
                        ->orWhere('email', 'like', $term);
                })
                ->orWhereHas('listing', function (Builder $q2) use ($term): void {
                    $q2->where('livestock_type', 'like', $term)
                        ->orWhere('breed', 'like', $term);
                });
        });
    }

    private function applyFilters(Builder $query, ?string $status, ?string $dateFrom, ?string $dateTo): void
    {
        if ($status !== null && $status !== '') {
            $query->where('status', TransactionStatus::from($status));
        }

        if ($dateFrom !== null && $dateFrom !== '') {
            $query->where('created_at', '>=', $dateFrom);
        }

        if ($dateTo !== null && $dateTo !== '') {
            $query->where('created_at', '<=', $dateTo.' 23:59:59');
        }
    }
}
