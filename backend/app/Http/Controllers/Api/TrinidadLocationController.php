<?php

namespace App\Http\Controllers\Api;

use App\Enums\TrinidadBarangay;
use App\Http\Controllers\Controller;
use App\Support\TrinidadLocationAddress;
use Illuminate\Http\JsonResponse;

/** Read-only location reference data for Trinidad, Bohol. */
class TrinidadLocationController extends Controller
{
    public function __invoke(): JsonResponse
    {
        return response()->json([
            'success' => true,
            'message' => 'Trinidad location catalog retrieved.',
            'data' => [
                'region' => TrinidadLocationAddress::REGION,
                'province' => TrinidadLocationAddress::PROVINCE,
                'municipality' => TrinidadLocationAddress::MUNICIPALITY,
                'barangays' => TrinidadBarangay::names(),
            ],
        ]);
    }
}
