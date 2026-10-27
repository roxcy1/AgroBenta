<?php

namespace App\Repositories\Admin;

use App\Enums\InquiryStatus;
use App\Models\Inquiry;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Builder;

class AdminInquiryRepository
{
    public function list(?string $search = null, ?string $status = null, int $perPage = 15): LengthAwarePaginator
    {
        $query = Inquiry::query()
            ->with([
                'buyer:id,name,email',
                'seller:id,name,email',
                'listing:id,livestock_type,breed',
            ]);

        $this->applySearch($query, $search);
        $this->applyFilters($query, $status);

        return $query
            ->orderByDesc('created_at')
            ->orderByDesc('id')
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
                ->orWhere('subject', 'like', $term)
                ->orWhere('message', 'like', $term)
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

    private function applyFilters(Builder $query, ?string $status): void
    {
        if ($status !== null && $status !== '') {
            $query->where('status', InquiryStatus::from($status));
        }
    }
}
