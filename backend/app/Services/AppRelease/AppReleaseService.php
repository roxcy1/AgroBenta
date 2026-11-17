<?php

namespace App\Services\AppRelease;

use Illuminate\Contracts\Filesystem\Filesystem;
use Illuminate\Support\Facades\Storage;
use InvalidArgumentException;

/**
 * The latest Android build of the AgroBenta mobile app.
 *
 * The APK is published to the `public` disk under `releases/`, so it is served
 * like any other public file (`APP_URL/storage/releases/...`). A small JSON
 * manifest on the private `local` disk records which file is current, so the
 * home page and the app's update check read one source.
 *
 * Releases are published from the command line (`app:publish-release`) by
 * whoever deploys the server; there is no upload endpoint.
 */
class AppReleaseService
{
    private const MANIFEST = 'app-release/latest.json';

    private const DIRECTORY = 'releases';

    /**
     * The current release, or null when none has been published.
     *
     * @return array{version_name: string, version_code: int, file: string, size_bytes: int, sha256: string, notes: ?string, published_at: string}|null
     */
    public function latest(): ?array
    {
        $raw = $this->manifestDisk()->get(self::MANIFEST);
        if ($raw === null) {
            return null;
        }

        $manifest = json_decode($raw, true);
        if (! is_array($manifest) || ! $this->apkDisk()->exists((string) ($manifest['file'] ?? ''))) {
            return null;
        }

        return $manifest;
    }

    /** The public URL of a published release file. */
    public function downloadUrl(array $release): string
    {
        return $this->apkDisk()->url($release['file']);
    }

    /**
     * Publish [$apkPath] as the new current release.
     *
     * The version code must be higher than the current one: Android refuses to
     * install an update whose code is not higher than the installed app's.
     *
     * @return array{version_name: string, version_code: int, file: string, size_bytes: int, sha256: string, notes: ?string, published_at: string}
     */
    public function publish(string $apkPath, string $versionName, int $versionCode, ?string $notes = null): array
    {
        if (! is_file($apkPath) || ! is_readable($apkPath)) {
            throw new InvalidArgumentException("The APK file [{$apkPath}] cannot be read.");
        }

        // An APK is a ZIP archive; anything else is the wrong file.
        $handle = fopen($apkPath, 'rb');
        $magic = $handle === false ? '' : (string) fread($handle, 4);
        if ($handle !== false) {
            fclose($handle);
        }
        if ($magic !== "PK\x03\x04") {
            throw new InvalidArgumentException('The file is not an APK.');
        }

        if (preg_match('/^\d+\.\d+\.\d+$/', $versionName) !== 1) {
            throw new InvalidArgumentException('The version name must look like 1.2.3.');
        }

        if ($versionCode < 1) {
            throw new InvalidArgumentException('The version code must be a positive number.');
        }

        $current = $this->latest();
        if ($current !== null && $versionCode <= $current['version_code']) {
            throw new InvalidArgumentException(
                "The version code must be higher than the current release ({$current['version_code']})."
            );
        }

        $file = self::DIRECTORY."/agrobenta-{$versionName}-{$versionCode}.apk";

        $stream = fopen($apkPath, 'rb');
        $this->apkDisk()->writeStream($file, $stream);
        if (is_resource($stream)) {
            fclose($stream);
        }

        $release = [
            'version_name' => $versionName,
            'version_code' => $versionCode,
            'file' => $file,
            'size_bytes' => (int) filesize($apkPath),
            'sha256' => (string) hash_file('sha256', $apkPath),
            'notes' => $notes !== null && trim($notes) !== '' ? trim($notes) : null,
            'published_at' => now()->toIso8601String(),
        ];

        $this->manifestDisk()->put(self::MANIFEST, json_encode($release, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));

        return $release;
    }

    private function apkDisk(): Filesystem
    {
        return Storage::disk('public');
    }

    private function manifestDisk(): Filesystem
    {
        return Storage::disk('local');
    }
}
