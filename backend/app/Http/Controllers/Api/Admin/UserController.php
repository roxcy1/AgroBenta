<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\DeactivateUserRequest;
use App\Http\Requests\Admin\ListUsersRequest;
use App\Http\Requests\Admin\ReactivateUserRequest;
use App\Http\Requests\Admin\UpdateUserRequest;
use App\Http\Resources\AdminUserResource;
use App\Models\User;
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
            status: $request->validated('status'),
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
     * record to focus on it rather than presenting a dead link. Deactivated
     * accounts remain readable through the explicit trashed route binding.
     */
    public function show(User $user): JsonResponse
    {
        return response()->json([
            'success' => true,
            'data' => new AdminUserResource($this->users->showUser($user)),
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

    /** Deactivate the account with a required administrative reason. */
    public function destroy(DeactivateUserRequest $request, User $user): JsonResponse
    {
        $deactivated = $this->users->deleteUser(
            $user,
            $request->user(),
            $request->validated('reason'),
        );

        return response()->json([
            'success' => true,
            'message' => 'User deactivated.',
            'data' => new AdminUserResource($deactivated),
        ], 200);
    }

    /** Restore a deactivated account with a required administrative reason. */
    public function reactivate(ReactivateUserRequest $request, User $user): JsonResponse
    {
        $reactivated = $this->users->reactivateUser(
            $user,
            $request->user(),
            $request->validated('reason'),
        );

        return response()->json([
            'success' => true,
            'message' => 'User reactivated.',
            'data' => new AdminUserResource($reactivated),
        ], 200);
    }
}
