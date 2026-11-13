<?php

namespace App\Services\SellerActivity;

use App\Models\Activity;
use App\Models\User;
use App\Repositories\SellerActivity\SellerActivityRepository;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Support\Collection;

/**
 * The seller's activity feed.
 *
 * The repository owns scoping, filtering and ordering; the resource owns the
 * projection. This service exists so the controller has one dependency and a
 * future additional source has a place to compose.
 */
class SellerActivityService
{
    public function __construct(private readonly SellerActivityRepository $activities)
    {
        //
    }

    /**
     * @return Collection<int, Activity>
     */
    public function latestForSeller(User $seller, int $limit = 5): Collection
    {
        return $this->activities->latestForSeller($seller, $limit);
    }

    /**
     * @return LengthAwarePaginator<int, Activity>
     */
    public function paginateForSeller(
        User $seller,
        int $perPage = 15,
        int $page = 1,
        ?string $category = null,
        ?string $from = null,
        ?string $to = null,
    ): LengthAwarePaginator {
        return $this->activities->paginateForSeller(
            $seller,
            $perPage,
            $page,
            $category,
            $from,
            $to,
        );
    }
}
