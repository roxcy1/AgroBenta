<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\ListUsersRequest;
use App\Http\Requests\Admin\UpdateUserRequest;
use App\Http\Resources\AdminUserResource;
use App\Models\User;
use App\Services\Admin\AdminUserService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

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

    /**
     * Show a single user.
     *
     * Deep-link support: the activity feed links to the acting user by id. The
     * users surface has no separate detail screen, so the list resolves this
     * record to focus on it rather than presenting a dead link.
     */
    public function show(User $user): JsonResponse
    {
        return response()->json([
            'success' => true,
            'data' => new AdminUserResource($user),
        ], 200);
    }

    /** Update the administrator-editable name and email fields. */
    public function update(UpdateUserRequest $request, User $user): JsonResponse
    {
        $updated = $this->users->updateUser(
            $user,
            $request->validated(),
            $request->user(),
        );

        return response()->json([
            'success' => true,
            'message' => 'User updated.',
            'data' => new AdminUserResource($updated),
        ], 200);
    }

    /** Soft-delete the account and revoke its active credentials. */
    public function destroy(Request $request, User $user): JsonResponse
    {
        $deleted = $this->users->deleteUser($user, $request->user());

        return response()->json([
            'success' => true,
            'message' => 'User deleted.',
            'data' => new AdminUserResource($deleted),
        ], 200);
    }
}
