<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use App\Http\Requests\Auth\LoginRequest;
use App\Http\Requests\Auth\RegisterRequest;
use App\Http\Resources\UserResource;
use App\Services\MobileAuthService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AuthController extends Controller
{
    public function __construct(private readonly MobileAuthService $auth)
    {
        //
    }

    /**
     * Register a normal user and issue a mobile-scoped bearer token.
     */
    public function register(RegisterRequest $request): JsonResponse
    {
        $result = $this->auth->register(
            $request->safe()->only(['name', 'email', 'password']),
        );

        return response()->json([
            'success' => true,
            'message' => 'Registered successfully.',
            'data' => [
                'token' => $result['token'],
                'token_type' => 'Bearer',
                'user' => new UserResource($result['user']),
            ],
        ], 201);
    }

    /**
     * Authenticate a normal user and issue a mobile-scoped bearer token.
     */
    public function login(LoginRequest $request): JsonResponse
    {
        $result = $this->auth->login(
            $request->validated('email'),
            $request->validated('password'),
        );

        if ($result['result'] === MobileAuthService::RESULT_INVALID_CREDENTIALS) {
            abort(401, 'Invalid credentials.');
        }

        if ($result['result'] === MobileAuthService::RESULT_NOT_PERMITTED) {
            abort(403, 'This account may not sign in to the mobile application.');
        }

        return response()->json([
            'success' => true,
            'message' => 'Logged in successfully.',
            'data' => [
                'token' => $result['token'],
                'token_type' => 'Bearer',
                'user' => new UserResource($result['user']),
            ],
        ], 200);
    }

    /**
     * Return the authenticated mobile user's own profile.
     */
    public function me(Request $request): JsonResponse
    {
        return response()->json([
            'success' => true,
            'data' => new UserResource($request->user()),
        ], 200);
    }

    /**
     * Revoke the current mobile user's bearer token.
     */
    public function logout(Request $request): JsonResponse
    {
        $this->auth->logout($request->user());

        return response()->json([
            'success' => true,
            'message' => 'Logged out successfully.',
        ], 200);
    }
}
