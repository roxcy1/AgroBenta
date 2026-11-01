<?php

namespace App\Http\Controllers\Api\Profile;

use App\Http\Controllers\Controller;
use App\Http\Requests\Profile\ChangePasswordRequest;
use App\Http\Requests\Profile\UpdateProfileRequest;
use App\Http\Resources\UserResource;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Hash;

/**
 * The authenticated user's own profile.
 *
 * Every endpoint resolves the user from the token, never from a route
 * parameter. That is what makes "read my profile" a path that cannot be
 * pointed at somebody else's account, mirroring the seller-verification
 * group's design.
 *
 * The response shape is a plain `UserResource` in the standard envelope, so the
 * mobile `User.fromJson` already knows how to parse it.
 */
class ProfileController extends Controller
{
    /**
     * `GET /api/profile` — the caller's own profile.
     */
    public function show(): JsonResponse
    {
        return response()->json([
            'success' => true,
            'data' => new UserResource(request()->user()),
        ], 200);
    }

    /**
     * `PUT /api/profile` — update the caller's own profile.
     *
     * Only the keys present in the request are written. `validated()` returns
     * exactly the fields the request contained and the rules allowed, so a
     * partial update leaves the other columns untouched.
     */
    public function update(UpdateProfileRequest $request): JsonResponse
    {
        $user = $request->user();
        $user->fill($request->validated());
        $user->save();

        return response()->json([
            'success' => true,
            'message' => 'Profile updated.',
            'data' => new UserResource($user->fresh()),
        ], 200);
    }

    /**
     * `PUT /api/profile/password` — change the caller's password.
     *
     * The old password is verified by the Form Request, so by the time this runs
     * the user has proven they know the current one. The hash cast on the model
     * takes care of hashing the new value; hashing here would double-hash it.
     */
    public function changePassword(ChangePasswordRequest $request): JsonResponse
    {
        $user = $request->user();
        $user->password = Hash::make($request->validated('password'));
        $user->save();

        $currentToken = $user->currentAccessToken();

        if ($currentToken !== null) {
            $user->tokens()
                ->where('id', '!=', $currentToken->id)
                ->delete();
        }

        return response()->json([
            'success' => true,
            'message' => 'Password changed.',
        ], 200);
    }
}