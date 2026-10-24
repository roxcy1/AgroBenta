<?php

namespace App\Services\Admin;

use App\Repositories\Admin\AdminActivityRepository;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;

class AdminActivityService
{
    public function __construct(private readonly AdminActivityRepository $activities)
    {
        //
    }

    public function listActivities(
        ?string $search = null,
        $action = null,
        ?string $userId = null,
        ?string $dateFrom = null,
        ?string $dateTo = null,
        int $perPage = 15,
    ): LengthAwarePaginator {
        return $this->activities->list($search, $action, $userId, $dateFrom, $dateTo, $perPage);
    }

    public function getSummaryLast24Hours(): array
    {
        return $this->activities->getSummaryLast24Hours();
    }
}
