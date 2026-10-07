<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;

class CurrentUserController extends Controller
{
    /**
     * The authenticated user behind the scaffold `GET /user` route.
     *
     * The route is controller-backed rather than a closure so the route cache
     * can compile (a closure cannot be serialized into the route cache), while
     * keeping the exact scaffold behaviour.
     */
    public function __invoke(Request $request)
    {
        return $request->user();
    }
}