<?php

namespace App\Services\Admin;

use App\Repositories\Admin\AdminTransactionRepository;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;

class AdminTransactionService
{
    public function __construct(private readonly AdminTransactionRepository $transactions)
    {
        //
    }

    public function listTransactions(
        ?string $search = null,
        ?string $status = null,
        ?string $dateFrom = null,
        ?string $dateTo = null,
        int $perPage = 15,
    ): LengthAwarePaginator {
        return $this->transactions->list($search, $status, $dateFrom, $dateTo, $perPage);
    }
}
