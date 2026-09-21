<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\UpdateSettingsRequest;
use App\Http\Resources\SettingResource;
use App\Services\Admin\AdminSettingService;
use Illuminate\Http\JsonResponse;

class SettingsController extends Controller
{
    public function __construct(private readonly AdminSettingService $settings)
    {
        //
    }

    /**
     * Return all settings grouped by group.
     */
    public function index(): JsonResponse
    {
        $grouped = $this->settings->getAllGrouped();

        $data = [];
        foreach ($grouped as $group => $settings) {
            $data[$group] = SettingResource::collection($settings);
        }

        return response()->json([
            'success' => true,
            'data' => $data,
        ], 200);
    }

    /**
     * Update allowed settings.
     */
    public function update(UpdateSettingsRequest $request): JsonResponse
    {
        $result = $this->settings->updateSettings($request->validated());

        $grouped = $this->settings->getAllGrouped();

        $data = [];
        foreach ($grouped as $group => $settings) {
            $data[$group] = SettingResource::collection($settings);
        }

        return response()->json([
            'success' => true,
            'message' => 'Settings updated.',
            'data' => $data,
            'updated' => $result['updated'],
            'rejected' => $result['rejected'],
        ], 200);
    }
}
