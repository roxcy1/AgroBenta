<?php

namespace App\Services\Admin;

use App\Repositories\Admin\AdminListingRepository;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;

class AdminListingService
{
    public function __construct(private readonly AdminListingRepository $listings)
    {
        //
    }

    public function listListings(
        ?string $search = null,
        ?string $livestockType = null,
        ?string $status = null,
        int $perPage = 15,
    ): LengthAwarePaginator {
        return $this->listings->list($search, $livestockType, $status, $perPage);
    }
}
