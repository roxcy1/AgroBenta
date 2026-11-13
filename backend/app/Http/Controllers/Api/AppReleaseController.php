<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\AppRelease\AppReleaseService;
use Illuminate\Http\JsonResponse;

/**
 * GET /api/app-release
 *
 * The latest Android app release, for the public home page's download button
 * and the mobile app's update check. Public: a signed-out visitor needs it to
 * download the app. `data` is null until a release is published.
 */
class AppReleaseController extends Controller
{
    public function __construct(
        private readonly AppReleaseService $releases,
    ) {}

    public function __invoke(): JsonResponse
    {
        $release = $this->releases->latest();

        return response()->json([
            'success' => true,
            'message' => $release === null
                ? 'No app release has been published yet.'
                : 'Latest app release retrieved.',
            'data' => $release === null ? null : [
                'version_name' => $release['version_name'],
                'version_code' => $release['version_code'],
                'download_url' => $this->releases->downloadUrl($release),
                'size_bytes' => $release['size_bytes'],
                'sha256' => $release['sha256'],
                'notes' => $release['notes'],
                'published_at' => $release['published_at'],
            ],
        ]);
    }
}
