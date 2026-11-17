<?php

namespace Tests\Feature\AppRelease;

use Illuminate\Support\Facades\Storage;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class AppReleaseTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        Storage::fake('public');
        Storage::fake('local');
    }

    /** A minimal file that starts like an APK (a ZIP archive). */
    private function fakeApk(string $contents = 'agrobenta'): string
    {
        $path = tempnam(sys_get_temp_dir(), 'apk');
        file_put_contents($path, "PK\x03\x04".$contents);

        return $path;
    }

    private function publish(string $apk, string $name, int $code, array $extra = []): int
    {
        return $this->artisan('app:publish-release', array_merge([
            'apk' => $apk,
            '--version-name' => $name,
            '--version-code' => $code,
        ], $extra))->run();
    }

    #[Test]
    public function the_endpoint_is_public_and_empty_before_any_release(): void
    {
        $this->getJson('/api/app-release')
            ->assertOk()
            ->assertJson(['success' => true, 'data' => null]);
    }

    #[Test]
    public function a_published_release_is_served_with_its_download_url(): void
    {
        $apk = $this->fakeApk();

        $this->artisan('app:publish-release', [
            'apk' => $apk,
            '--version-name' => '1.0.0',
            '--version-code' => 1,
            '--notes' => 'First release.',
        ])->expectsOutputToContain('Published AgroBenta 1.0.0 (build 1).')->assertSuccessful();

        Storage::disk('public')->assertExists('releases/agrobenta-1.0.0-1.apk');

        $this->getJson('/api/app-release')
            ->assertOk()
            ->assertJsonPath('data.version_name', '1.0.0')
            ->assertJsonPath('data.version_code', 1)
            ->assertJsonPath('data.size_bytes', filesize($apk))
            ->assertJsonPath('data.sha256', hash_file('sha256', $apk))
            ->assertJsonPath('data.notes', 'First release.')
            ->assertJsonPath('data.download_url', Storage::disk('public')->url('releases/agrobenta-1.0.0-1.apk'));
    }

    #[Test]
    public function a_newer_build_replaces_the_current_release(): void
    {
        $this->assertSame(0, $this->publish($this->fakeApk('one'), '1.0.0', 1));
        $this->assertSame(0, $this->publish($this->fakeApk('two'), '1.0.1', 2));

        $this->getJson('/api/app-release')
            ->assertJsonPath('data.version_name', '1.0.1')
            ->assertJsonPath('data.version_code', 2)
            ->assertJsonPath('data.notes', null);

        // The previous file is kept, so a bad release can be rolled back.
        Storage::disk('public')->assertExists('releases/agrobenta-1.0.0-1.apk');
    }

    #[Test]
    public function the_version_code_must_increase(): void
    {
        $this->publish($this->fakeApk(), '1.0.1', 2);

        $this->artisan('app:publish-release', [
            'apk' => $this->fakeApk(),
            '--version-name' => '1.0.2',
            '--version-code' => 2,
        ])->expectsOutputToContain('higher than the current release (2)')->assertFailed();

        $this->getJson('/api/app-release')->assertJsonPath('data.version_name', '1.0.1');
    }

    #[Test]
    public function a_file_that_is_not_an_apk_is_refused(): void
    {
        $path = tempnam(sys_get_temp_dir(), 'txt');
        file_put_contents($path, 'not an archive');

        $this->artisan('app:publish-release', [
            'apk' => $path,
            '--version-name' => '1.0.0',
            '--version-code' => 1,
        ])->expectsOutputToContain('not an APK')->assertFailed();

        $this->getJson('/api/app-release')->assertJsonPath('data', null);
    }

    #[Test]
    public function the_version_options_are_validated(): void
    {
        $apk = $this->fakeApk();

        $this->artisan('app:publish-release', ['apk' => $apk, '--version-code' => 1])->assertFailed();
        $this->artisan('app:publish-release', ['apk' => $apk, '--version-name' => '1.0.0', '--version-code' => 'two'])->assertFailed();
        $this->artisan('app:publish-release', ['apk' => $apk, '--version-name' => 'v1', '--version-code' => 1])
            ->expectsOutputToContain('1.2.3')->assertFailed();
        $this->artisan('app:publish-release', ['apk' => '/no/such/file.apk', '--version-name' => '1.0.0', '--version-code' => 1])
            ->expectsOutputToContain('cannot be read')->assertFailed();

        Storage::disk('public')->assertDirectoryEmpty('releases');
    }

    #[Test]
    public function a_manifest_whose_file_is_missing_is_treated_as_no_release(): void
    {
        $this->publish($this->fakeApk(), '1.0.0', 1);
        Storage::disk('public')->delete('releases/agrobenta-1.0.0-1.apk');

        $this->getJson('/api/app-release')->assertJsonPath('data', null);
    }
}
