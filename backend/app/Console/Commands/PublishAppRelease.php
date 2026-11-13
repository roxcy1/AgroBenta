<?php

namespace App\Console\Commands;

use App\Services\AppRelease\AppReleaseService;
use Illuminate\Console\Command;
use InvalidArgumentException;

/**
 * Publish a built Android APK as the latest app release.
 *
 *   php artisan app:publish-release /tmp/app-release.apk --version-name=1.0.1 --version-code=2
 *
 * The version name and code must match `version:` in mobile/pubspec.yaml
 * (`1.0.1+2` is name 1.0.1, code 2), because the app compares the server's code
 * with its own to decide whether an update is available.
 */
class PublishAppRelease extends Command
{
    protected $signature = 'app:publish-release
        {apk : Path to the release APK}
        {--version-name= : The version name, e.g. 1.0.1}
        {--version-code= : The build number, higher than the current release}
        {--notes= : Optional short "what\'s new" text}';

    protected $description = 'Publish a built Android APK as the latest app release';

    public function handle(AppReleaseService $releases): int
    {
        $name = (string) $this->option('version-name');
        $code = $this->option('version-code');

        if ($name === '' || $code === null || ! ctype_digit((string) $code)) {
            $this->error('Pass --version-name (e.g. 1.0.1) and a numeric --version-code.');

            return self::FAILURE;
        }

        try {
            $release = $releases->publish(
                (string) $this->argument('apk'),
                $name,
                (int) $code,
                $this->option('notes'),
            );
        } catch (InvalidArgumentException $exception) {
            $this->error($exception->getMessage());

            return self::FAILURE;
        }

        $this->info("Published AgroBenta {$release['version_name']} (build {$release['version_code']}).");
        $this->line('Download: '.$releases->downloadUrl($release));

        return self::SUCCESS;
    }
}
