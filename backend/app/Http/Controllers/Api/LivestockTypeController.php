<?php

namespace App\Http\Controllers\Api;

use App\Enums\LivestockType;
use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;

class LivestockTypeController extends Controller
{
    /**
     * Return the approved livestock-type catalog.
     *
     * This endpoint intentionally answers with the raw `{ "data": [...] }`
     * shape rather than the project success envelope, so both clients consume
     * the same exact contract.
     */
    public function __invoke(): JsonResponse
    {
        return response()->json([
            'data' => LivestockType::options(),
        ]);
    }
}
