<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\ListUsersRequest;
use App\Http\Resources\AdminUserResource;
use App\Services\Admin\AdminUserService;
use Illuminate\Http\JsonResponse;

class UserController extends Controller
{
    public function __construct(private readonly AdminUserService $users)
    {
        //
    }

    /**
     * List users with optional search, filtering, and pagination.
     */
    public function index(ListUsersRequest $request): JsonResponse
    {
        $paginator = $this->users->listUsers(
            search: $request->validated('search'),
            role: $request->validated('role'),
            sellerCapability: $request->validated('seller_capability'),
            perPage: $request->validated('per_page', 15),
        );

        return response()->json([
            'success' => true,
            'data' => [
                'users' => AdminUserResource::collection($paginator->items()),
                'pagination' => [
                    'current_page' => $paginator->currentPage(),
                    'last_page' => $paginator->lastPage(),
                    'per_page' => $paginator->perPage(),
                    'total' => $paginator->total(),
                ],
            ],
        ], 200);
    }
}
