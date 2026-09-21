<?php

namespace App\Repositories\Admin;

use App\Enums\ListingStatus;
use App\Models\Listing;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Builder;

class AdminListingRepository
{
    public function list(
        ?string $search = null,
        ?string $livestockType = null,
        ?string $status = null,
        int $perPage = 15,
    ): LengthAwarePaginator {
        $query = Listing::with('seller:id,name,email');

        $this->applySearch($query, $search);
        $this->applyFilters($query, $livestockType, $status);

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
            $q->where('livestock_type', 'like', $term)
                ->orWhere('breed', 'like', $term)
                ->orWhere('location', 'like', $term);
        });
    }

    private function applyFilters(Builder $query, ?string $livestockType, ?string $status): void
    {
        if ($livestockType !== null && $livestockType !== '') {
            $query->where('livestock_type', $livestockType);
        }

        if ($status !== null && $status !== '') {
            $query->where('status', ListingStatus::from($status));
        }
    }
}
