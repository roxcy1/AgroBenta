<?php

namespace App\Services\Admin;

use App\Repositories\Admin\AdminUserRepository;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;

class AdminUserService
{
    public function __construct(private readonly AdminUserRepository $users)
    {
        //
    }

    public function listUsers(
        ?string $search = null,
        ?string $role = null,
        ?string $sellerCapability = null,
        int $perPage = 15,
    ): LengthAwarePaginator {
        return $this->users->list($search, $role, $sellerCapability, $perPage);
    }
}
