<?php

namespace App\Repositories\Admin;

use App\Enums\SellerVerificationStatus;
use App\Models\SellerVerification;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Builder;

class AdminSellerVerificationRepository
{
    public function list(
        ?string $search = null,
        ?string $status = null,
        int $perPage = 15,
    ): LengthAwarePaginator {
        $query = SellerVerification::with(['seller:id,name,email', 'reviewer:id,name']);

        $this->applySearch($query, $search);
        $this->applyFilters($query, $status);

        return $query
            ->orderByDesc('created_at')
            ->paginate($perPage);
    }

    public function find(int $id): ?SellerVerification
    {
        return SellerVerification::with(['seller:id,name,email', 'reviewer:id,name'])
            ->find($id);
    }

    private function applySearch(Builder $query, ?string $search): void
    {
        if ($search === null || $search === '') {
            return;
        }

        $term = '%'.$search.'%';

        $query->where(function (Builder $q) use ($term): void {
            $q->where('business_name', 'like', $term)
                ->orWhereHas('seller', function (Builder $sq) use ($term): void {
                    $sq->where('name', 'like', $term)
                        ->orWhere('email', 'like', $term);
                });
        });
    }

    private function applyFilters(Builder $query, ?string $status): void
    {
        if ($status !== null && $status !== '') {
            $query->where('status', SellerVerificationStatus::from($status));
        }
    }
}
