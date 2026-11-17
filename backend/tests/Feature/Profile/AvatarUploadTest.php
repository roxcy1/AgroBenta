<?php

namespace Tests\Feature\Profile;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Testing\TestResponse;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Profile avatar upload — `POST /api/profile/avatar`.
 *
 * Two things are pinned down here. The happy path writes the file inside the
 * caller's own `avatars/{userId}/` directory and persists the resulting URL.
 * The deletion path is the delicate one: a previous `avatar_url` is only a
 * delete target when it resolves inside that same directory, so an external
 * URL, a traversal attempt, or another account's file must survive untouched.
 */
class AvatarUploadTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        // The `url` is passed explicitly so the fake disk resolves URLs exactly
        // as the real one does; otherwise a faked local disk can fall back to a
        // relative path and the ownership checks would test the wrong thing.
        Storage::fake('public', [
            'url' => config('filesystems.disks.public.url'),
        ]);
    }

    private function mobileToken(User $user): string
    {
        return $user->createToken('mobile', ['mobile'])->plainTextToken;
    }

    private function upload(User $user, UploadedFile $file, ?string $token = null): TestResponse
    {
        return $this->withHeader(
            'Authorization',
            'Bearer '.($token ?? $this->mobileToken($user)),
        )->post('/api/profile/avatar', ['avatar' => $file]);
    }

    /**
     * A minimal real JPEG (1×1), written with content because the container's
     * GD has no JPEG encoder — and because content, not the file name, is what
     * the mime allow-list should be tested against anyway.
     */
    private function tinyJpeg(string $name = 'avatar.jpg'): UploadedFile
    {
        return UploadedFile::fake()->createWithContent(
            $name,
            base64_decode(
                '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof'.
                'Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAAB'.
                'AAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q=='
            ),
        );
    }

    /**
     * A real JPEG header (so the mime allow-list passes on content) padded
     * beyond 5 MB (so only the size rule can reject it).
     */
    private function oversizedJpeg(): UploadedFile
    {
        $header = base64_decode(
            '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof'.
            'Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAAB'.
            'AAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q=='
        );

        return UploadedFile::fake()->createWithContent('big.jpg', $header.str_repeat('A', 6 * 1024 * 1024));
    }

    /**
     * The disk path behind a stored avatar URL.
     */
    private function storedPath(string $url): string
    {
        $base = Storage::disk('public')->url('');

        return ltrim(substr($url, strlen($base)), '/');
    }

    #[Test]
    public function an_authenticated_user_can_upload_an_avatar(): void
    {
        $user = User::factory()->create();

        $response = $this->upload($user, $this->tinyJpeg())
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('message', 'Profile picture updated.');

        $user->refresh();
        $path = $this->storedPath($user->avatar_url);

        $this->assertNotSame('', $path);
        $this->assertStringStartsWith("avatars/{$user->id}/", $path);
        Storage::disk('public')->assertExists($path);
        $response->assertJsonPath('data.avatar_url', $user->avatar_url);
    }

    #[Test]
    public function replacing_an_avatar_deletes_the_previous_own_file(): void
    {
        $user = User::factory()->create();
        $oldPath = "avatars/{$user->id}/old.jpg";

        Storage::disk('public')->put($oldPath, 'old avatar');
        $user->avatar_url = Storage::disk('public')->url($oldPath);
        $user->save();

        $this->upload($user, $this->tinyJpeg('new.jpg'))->assertOk();

        $user->refresh();
        $newPath = $this->storedPath($user->avatar_url);

        Storage::disk('public')->assertMissing($oldPath);
        Storage::disk('public')->assertExists($newPath);
        $this->assertNotSame($oldPath, $newPath);
    }

    #[Test]
    public function the_old_avatar_of_another_user_is_never_deleted(): void
    {
        $user = User::factory()->create();
        $otherUser = User::factory()->create();
        $victimPath = "avatars/{$otherUser->id}/victim.jpg";

        Storage::disk('public')->put($victimPath, 'not mine');

        // A tampered or stale URL must not become a delete capability.
        $user->avatar_url = Storage::disk('public')->url($victimPath);
        $user->save();

        $this->upload($user, $this->tinyJpeg())->assertOk();

        Storage::disk('public')->assertExists($victimPath);
        $this->assertStringStartsWith(
            "avatars/{$user->id}/",
            $this->storedPath($user->fresh()->avatar_url),
        );
    }

    #[Test]
    public function a_path_traversal_avatar_url_is_never_deleted(): void
    {
        $user = User::factory()->create();
        $otherUser = User::factory()->create();
        $victimPath = "avatars/{$otherUser->id}/victim.jpg";

        Storage::disk('public')->put($victimPath, 'not mine');

        $user->avatar_url = Storage::disk('public')->url(
            "avatars/{$user->id}/../{$otherUser->id}/victim.jpg",
        );
        $user->save();

        $this->upload($user, $this->tinyJpeg())->assertOk();

        Storage::disk('public')->assertExists($victimPath);
    }

    #[Test]
    public function a_non_image_file_is_rejected(): void
    {
        $user = User::factory()->create();

        $this->upload($user, UploadedFile::fake()->create('notes.pdf', 10, 'application/pdf'))
            ->assertUnprocessable()
            ->assertJsonValidationErrors('avatar');

        $this->assertNull($user->fresh()->avatar_url);
        $this->assertSame([], Storage::disk('public')->allFiles());
    }

    #[Test]
    public function an_avatar_larger_than_five_megabytes_is_rejected(): void
    {
        $user = User::factory()->create();

        $this->upload($user, $this->oversizedJpeg())
            ->assertUnprocessable()
            // The size rule specifically - not a side-effect of another rule.
            ->assertJsonValidationErrors(['avatar' => 'greater than 5120']);

        $this->assertNull($user->fresh()->avatar_url);
        $this->assertSame([], Storage::disk('public')->allFiles());
    }

    #[Test]
    public function an_unauthenticated_upload_is_rejected(): void
    {
        $user = User::factory()->create();

        $this->post('/api/profile/avatar', ['avatar' => $this->tinyJpeg()])
            ->assertUnauthorized();

        $this->assertNull($user->fresh()->avatar_url);
        $this->assertSame([], Storage::disk('public')->allFiles());
    }
}
