<?php

namespace Tests\Feature\SellerListing;

use App\Enums\ListingStatus;
use App\Enums\UserRole;
use App\Models\Activity;
use App\Models\Listing;
use App\Models\Setting;
use App\Models\User;
use App\Services\SellerListing\SellerListingService;
use Illuminate\Contracts\Filesystem\Filesystem;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Testing\TestResponse;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Listing photos — functional documentation §4.5, contract D-10.
 *
 * Two representations, one column, no migration: the JSON stores bare
 * filenames, and the API serves absolute URLs resolved by the `Listing`
 * accessor. Everything below pins that decision down from both sides — what
 * lands in the database, what leaves in the response — and holds the line on
 * the security rules that made this endpoint delicate: the file allow-list,
 * the 10-photo ceiling across *both* write paths, and 404 (never 403) for an
 * id that is not the caller's.
 */
class SellerListingPhotoTest extends TestCase
{
    use RefreshDatabase;

    private User $seller;

    private User $otherSeller;

    private User $buyer;

    protected function setUp(): void
    {
        parent::setUp();

        // The `url` is passed explicitly so the fake disk resolves URLs exactly
        // as the real one does; without it a faked local disk can fall back to
        // a relative path and the absolute-URL assertions would be testing the
        // wrong thing.
        Storage::fake(Listing::PHOTO_DISK, [
            'url' => config('filesystems.disks.listing-photos.url'),
        ]);

        $this->seller = User::factory()->seller()->create([
            'role' => UserRole::User,
            'name' => 'Juan Dela Cruz',
            'email' => 'juan@agrobenta.test',
        ]);

        $this->otherSeller = User::factory()->seller()->create([
            'role' => UserRole::User,
            'name' => 'Maria Santos',
            'email' => 'maria@agrobenta.test',
        ]);

        $this->buyer = User::factory()->create([
            'role' => UserRole::User,
            'name' => 'Pedro Reyes',
        ]);
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function createListing(User $seller, array $overrides = []): Listing
    {
        return Listing::create(array_merge([
            'seller_id' => $seller->id,
            'livestock_type' => 'cattle',
            'breed' => 'Angus',
            'age_value' => 2,
            'age_unit' => 'year',
            'gender' => 'male',
            'weight_value' => 500,
            'weight_unit' => 'kg',
            'quantity' => 1,
            'asking_price' => 50000.00,
            'location' => 'Bukidnon',
            'health_status' => 'healthy',
            'vaccination' => 'up_to_date',
            'short_description' => 'Healthy Angus bull',
            'additional_notes' => null,
            'photos' => [],
            'status' => ListingStatus::Draft,
        ], $overrides));
    }

    private function mobileToken(User $user): string
    {
        return $user->createToken('mobile', ['mobile'])->plainTextToken;
    }

    private function photoBase(): string
    {
        return (string) config('filesystems.disks.listing-photos.url');
    }

    /**
     * The filenames exactly as persisted — re-read from storage, never through
     * the URL accessor.
     *
     * @return list<string>
     */
    private function storedPhotos(Listing $listing): array
    {
        return Listing::query()->findOrFail($listing->id)->storedPhotoFilenames();
    }

    /**
     * Write real files into a listing's own photo directory.
     *
     * The set-at-once edit path accepts only filenames that already exist
     * there, so a fixture must put them there instead of asserting a name with
     * no file behind it.
     *
     * @param  list<string>  $filenames
     */
    private function writePhotoFiles(Listing $listing, array $filenames): void
    {
        $disk = Storage::disk(Listing::PHOTO_DISK);

        foreach ($filenames as $filename) {
            $disk->put($listing->id.'/'.$filename, 'photo');
        }
    }

    /**
     * @param  array<int, UploadedFile>  $files
     */
    private function upload(Listing $listing, array $files, ?string $token = null): TestResponse
    {
        return $this->withHeader(
            'Authorization',
            'Bearer '.($token ?? $this->mobileToken($this->seller)),
        )->post("/api/seller/listings/{$listing->id}/photos", ['photos' => $files]);
    }

    private function removePhoto(Listing $listing, string $photo, ?string $token = null): TestResponse
    {
        return $this->withHeader(
            'Authorization',
            'Bearer '.($token ?? $this->mobileToken($this->seller)),
        )->delete("/api/seller/listings/{$listing->id}/photos", ['photo' => $photo]);
    }

    /**
     * A minimal real JPEG (1×1), written with content because the container's
     * GD has no JPEG encoder — and because content, not the file name, is what
     * the mime allow-list should be tested against anyway.
     */
    private function tinyJpeg(string $name = 'photo.jpg'): UploadedFile
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
     * A minimal real PNG (1×1), for the same reasons.
     */
    private function tinyPng(string $name = 'photo.png'): UploadedFile
    {
        return UploadedFile::fake()->createWithContent(
            $name,
            base64_decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGA'.
                'hKmMIQAAAABJRU5ErkJggg=='
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
     * A minimal real WEBP (RIFF…WEBP), so acceptance is proven on content
     * rather than on a name the validator might not trust.
     */
    private function tinyWebp(): UploadedFile
    {
        return UploadedFile::fake()->createWithContent(
            'pic.webp',
            base64_decode('UklGRiQAAABXRUJQVlA4IBgAAAAwAQCdASoBAAEAAwA0JaQAA3AA/vuUAAA='),
        );
    }

    // ---------------------------------------------------------------- upload

    #[Test]
    public function photos_upload_store_filenames_and_return_absolute_urls(): void
    {
        $listing = $this->createListing($this->seller);

        $response = $this->upload($listing, [
            $this->tinyJpeg('front.jpg'),
            $this->tinyPng('side.png'),
        ])->assertStatus(201);

        $stored = $this->storedPhotos($listing);
        $served = $response->json('data.photos');

        // Storage holds bare filenames — no directories, no URLs, no slashes.
        $this->assertCount(2, $stored);

        foreach ($stored as $filename) {
            $this->assertMatchesRegularExpression('/^[A-Za-z0-9]+\.(jpg|png)$/', $filename);
            Storage::disk(Listing::PHOTO_DISK)->assertExists($listing->id.'/'.$filename);
        }

        // The response holds the same two photos as absolute URLs, in order —
        // the URL of each photo names the file actually stored.
        $this->assertSame(
            array_map(
                fn (string $filename): string => $this->photoBase().'/'.$listing->id.'/'.$filename,
                $stored,
            ),
            $served,
        );

        foreach ($served as $url) {
            $this->assertStringStartsWith('http', $url);
        }
    }

    #[Test]
    public function photos_are_appended_across_uploads(): void
    {
        $listing = $this->createListing($this->seller);

        $this->upload($listing, [$this->tinyJpeg('front.jpg')])
            ->assertStatus(201)
            ->assertJsonCount(1, 'data.photos');

        $this->upload($listing, [$this->tinyJpeg('side.jpg')])
            ->assertStatus(201)
            ->assertJsonCount(2, 'data.photos');

        $this->assertCount(2, $this->storedPhotos($listing));
    }

    #[Test]
    public function webp_uploads_are_accepted(): void
    {
        $listing = $this->createListing($this->seller);

        $this->upload($listing, [$this->tinyWebp()])
            ->assertStatus(201)
            ->assertJsonCount(1, 'data.photos');
    }

    // ------------------------------------------------------------- rejection

    #[Test]
    public function a_file_outside_the_mime_allow_list_is_rejected(): void
    {
        $listing = $this->createListing($this->seller);

        $this->upload($listing, [UploadedFile::fake()->create('anim.gif', 100, 'image/gif')])
            ->assertStatus(422)
            ->assertJsonValidationErrors('photos.0');

        $this->assertSame([], $this->storedPhotos($listing));
    }

    #[Test]
    public function a_file_larger_than_five_megabytes_is_rejected(): void
    {
        $listing = $this->createListing($this->seller);

        $this->upload($listing, [$this->oversizedJpeg()])
            ->assertStatus(422)
            // The size rule specifically — not a side-effect of another rule.
            ->assertJsonValidationErrors(['photos.0' => 'greater than 5120']);

        $this->assertSame([], $this->storedPhotos($listing));
    }

    #[Test]
    public function more_than_ten_photos_in_one_request_is_rejected(): void
    {
        $listing = $this->createListing($this->seller);

        $files = [];

        for ($i = 0; $i < 11; $i++) {
            $files[] = $this->tinyJpeg("photo{$i}.jpg");
        }

        $this->upload($listing, $files)
            ->assertStatus(422)
            ->assertJsonValidationErrors('photos');

        $this->assertSame([], $this->storedPhotos($listing));
    }

    #[Test]
    public function an_upload_beyond_the_stored_limit_is_rejected(): void
    {
        $listing = $this->createListing($this->seller, [
            'photos' => ['a.jpg', 'b.jpg', 'c.jpg', 'd.jpg', 'e.jpg', 'f.jpg', 'g.jpg', 'h.jpg', 'i.jpg'],
        ]);

        // Two files pass the per-request ceiling; nine stored plus two new
        // would break the per-listing one — which is the service's check to
        // make, because only it can see the stored count.
        $this->upload($listing, [
            $this->tinyJpeg('one-more.jpg'),
            $this->tinyJpeg('two-more.jpg'),
        ])->assertStatus(422)->assertJsonValidationErrors('photos');

        $this->assertCount(9, $this->storedPhotos($listing));
    }

    #[Test]
    public function a_listing_cannot_be_created_with_more_than_ten_photos(): void
    {
        // Eleven placeholders on create: the set-at-once path must not be a
        // way around the upload path's ceiling.
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings', [
                'livestock_type' => 'cattle',
                'location' => 'Bukidnon',
                'asking_price' => 50000,
                'quantity' => 1,
                'photos' => array_fill(0, 11, 'photo.jpg'),
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('photos');
    }

    #[Test]
    public function a_listing_can_be_created_without_photos_but_not_with_them(): void
    {
        // A draft stays photo-optional: the upload endpoints attach photos once
        // the listing exists and has an id to scope a directory to.
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings', [
                'livestock_type' => 'cattle',
                'location' => 'Bukidnon',
                'asking_price' => 50000,
                'quantity' => 1,
                'photos' => [],
            ])
            ->assertCreated()
            ->assertJsonPath('data.photos', []);

        // A non-empty list is a claim the server cannot verify: there is no
        // directory for this listing yet, so it is refused at any size.
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings', [
                'livestock_type' => 'cattle',
                'location' => 'Bukidnon',
                'asking_price' => 50000,
                'quantity' => 1,
                'photos' => ['photo.jpg'],
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('photos');
    }

    // --------------------------------------------------- edit (set-at-once)

    #[Test]
    public function an_update_accepts_a_filename_that_exists_on_the_listing(): void
    {
        $listing = $this->createListing($this->seller);
        $this->writePhotoFiles($listing, ['front.jpg', 'side.jpg']);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson("/api/seller/listings/{$listing->id}", [
                'photos' => ['front.jpg'],
            ])
            ->assertOk()
            ->assertJsonCount(1, 'data.photos');

        $this->assertSame(['front.jpg'], $this->storedPhotos($listing));
    }

    #[Test]
    public function an_update_accepts_the_url_it_was_served(): void
    {
        $listing = $this->createListing($this->seller);
        $this->writePhotoFiles($listing, ['front.jpg']);

        // A client holds URLs, so a read-modify-write round trip must not force
        // it to parse its own URL into a filename first.
        $served = $this->photoBase().'/'.$listing->id.'/front.jpg';

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson("/api/seller/listings/{$listing->id}", [
                'photos' => [$served],
            ])
            ->assertOk();

        $this->assertSame(['front.jpg'], $this->storedPhotos($listing));
    }

    #[Test]
    public function an_update_rejects_a_filename_that_has_no_file(): void
    {
        $listing = $this->createListing($this->seller);
        $this->writePhotoFiles($listing, ['front.jpg']);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson("/api/seller/listings/{$listing->id}", [
                'photos' => ['ghost.jpg'],
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('photos');

        // Refused, not applied.
        $this->assertSame([], $this->storedPhotos($listing));
    }

    #[Test]
    public function an_update_cannot_adopt_another_listings_photo(): void
    {
        $other = $this->createListing($this->otherSeller);
        $this->writePhotoFiles($other, ['foreign.jpg']);

        $listing = $this->createListing($this->seller);

        // Even the other listing's served URL collapses to a filename that this
        // listing's own directory does not contain.
        $foreignUrl = $this->photoBase().'/'.$other->id.'/foreign.jpg';

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson("/api/seller/listings/{$listing->id}", [
                'photos' => [$foreignUrl],
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('photos');

        $this->assertSame([], $this->storedPhotos($listing));
    }

    #[Test]
    public function an_update_cannot_escape_the_listing_directory(): void
    {
        $other = $this->createListing($this->otherSeller);
        $this->writePhotoFiles($other, ['foreign.jpg']);

        $listing = $this->createListing($this->seller);

        // The mutator's basename rule turns this into `foreign.jpg`, which is
        // still not in *this* listing's directory.
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson("/api/seller/listings/{$listing->id}", [
                'photos' => ['../'.$other->id.'/foreign.jpg'],
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('photos');

        $this->assertSame([], $this->storedPhotos($listing));
    }

    #[Test]
    public function an_active_listing_cannot_be_edited_to_have_no_photos(): void
    {
        $listing = $this->createListing($this->seller, [
            'status' => ListingStatus::Active,
            'photos' => ['only.jpg'],
        ]);
        $this->writePhotoFiles($listing, ['only.jpg']);

        // The same rule as removing the last photo: an edit is not a route
        // around the requirement that a live listing keeps one photo.
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson("/api/seller/listings/{$listing->id}", ['photos' => []])
            ->assertStatus(422)
            ->assertJsonValidationErrors('photos');

        $this->assertSame(['only.jpg'], $this->storedPhotos($listing));
    }

    #[Test]
    public function a_draft_can_be_edited_to_have_no_photos(): void
    {
        $listing = $this->createListing($this->seller, ['photos' => ['only.jpg']]);
        $this->writePhotoFiles($listing, ['only.jpg']);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson("/api/seller/listings/{$listing->id}", ['photos' => []])
            ->assertOk()
            ->assertJsonPath('data.photos', []);

        $this->assertSame([], $this->storedPhotos($listing));
    }

    // ------------------------------------------------- configurable ceiling

    /**
     * Write a `listing.max_photos` setting row directly, bypassing the admin
     * API so the consumer behaviour is tested in isolation.
     */
    private function setPhotoLimit(string $value): void
    {
        Setting::create([
            'key' => 'listing.max_photos',
            'value' => $value,
            'group' => 'listings',
            'label' => 'Maximum Photos per Listing',
            'description' => 'The most photos a single listing may hold.',
        ]);
    }

    #[Test]
    public function the_photo_ceiling_follows_the_setting(): void
    {
        $this->setPhotoLimit('3');

        $listing = $this->createListing($this->seller);

        $files = [];

        for ($i = 0; $i < 4; $i++) {
            $files[] = $this->tinyJpeg("photo{$i}.jpg");
        }

        $this->upload($listing, $files)
            ->assertStatus(422)
            ->assertJsonValidationErrors('photos');

        $this->assertSame([], $this->storedPhotos($listing));
    }

    #[Test]
    public function a_configured_ceiling_does_not_make_photos_valid_on_create(): void
    {
        $this->setPhotoLimit('3');

        // Lowering the ceiling changes the upload and edit bound; it does not
        // create a way to attach a file to a listing that does not exist yet.
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings', [
                'livestock_type' => 'cattle',
                'location' => 'Bukidnon',
                'asking_price' => 50000,
                'quantity' => 1,
                'photos' => ['photo1.jpg', 'photo2.jpg'],
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('photos');
    }

    #[Test]
    public function a_malformed_photo_ceiling_setting_falls_back_to_the_default(): void
    {
        // Garbage in the setting must not disable the limit: the code's own
        // ceiling of 10 still rejects the eleventh photo.
        $this->setPhotoLimit('not-a-number');

        $listing = $this->createListing($this->seller);

        $files = [];

        for ($i = 0; $i < 11; $i++) {
            $files[] = $this->tinyJpeg("photo{$i}.jpg");
        }

        $this->upload($listing, $files)
            ->assertStatus(422)
            ->assertJsonValidationErrors('photos');
    }

    /**
     * A stored ceiling outside the registry bounds is as invalid as garbage, and
     * must resolve to the documented default rather than to itself.
     *
     * The value is written straight to the table, bypassing the admin API — the
     * only way an out-of-bounds row can exist — so this is the consumer's own
     * defence, not the writer's. Each case proves both halves: the bad value does
     * not raise the ceiling (11 files are rejected) and does not *lower* it to
     * zero (exactly 10 files are still accepted).
     */
    #[Test]
    #[DataProvider('outOfBoundsPhotoCeilings')]
    public function an_out_of_bounds_photo_ceiling_falls_back_to_the_default(string $value): void
    {
        $this->setPhotoLimit($value);

        $listing = $this->createListing($this->seller);

        $eleven = [];

        for ($i = 0; $i < 11; $i++) {
            $eleven[] = $this->tinyJpeg("over{$i}.jpg");
        }

        $this->upload($listing, $eleven)
            ->assertStatus(422)
            ->assertJsonValidationErrors('photos');

        $this->assertSame([], $this->storedPhotos($listing));

        $ten = [];

        for ($i = 0; $i < 10; $i++) {
            $ten[] = $this->tinyJpeg("ok{$i}.jpg");
        }

        $this->upload($listing, $ten)
            ->assertStatus(201)
            ->assertJsonCount(10, 'data.photos');
    }

    /**
     * @return array<string, array{string}>
     */
    public static function outOfBoundsPhotoCeilings(): array
    {
        return [
            'zero' => ['0'],
            'negative' => ['-1'],
            'above the registry maximum' => ['51'],
        ];
    }

    #[Test]
    public function the_photo_ceiling_applies_when_editing_with_the_setting(): void
    {
        // The *edit* path must honour the same ceiling as upload and create: a
        // listing cannot be PATCHed past it.
        $this->setPhotoLimit('2');

        $listing = $this->createListing($this->seller);
        $this->writePhotoFiles($listing, ['a.jpg', 'b.jpg', 'c.jpg']);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson("/api/seller/listings/{$listing->id}", [
                'photos' => ['a.jpg', 'b.jpg', 'c.jpg'],
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('photos');

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson("/api/seller/listings/{$listing->id}", [
                'photos' => ['a.jpg', 'b.jpg'],
            ])
            ->assertOk();
    }

    #[Test]
    public function updating_the_photo_ceiling_takes_effect_for_uploads(): void
    {
        // Warm the settings cache first, so this proves the write path drops a
        // populated cache rather than merely reading a cold one.
        $listing = $this->createListing($this->seller);

        $this->upload($listing, [$this->tinyJpeg('first.jpg')])->assertStatus(201);

        $admin = User::factory()->create(['role' => UserRole::Admin]);
        $token = $admin->createToken('admin_token', ['admin'])->plainTextToken;

        // Uploading above authenticated the seller; the resolved user is memoised
        // on the guard, so a fresh identity needs the guards reset first.
        app('auth')->forgetGuards();

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->putJson('/api/admin/settings', ['listing.max_photos' => '3'])
            ->assertOk()
            ->assertJsonPath('updated', ['listing.max_photos']);

        $files = [];

        for ($i = 0; $i < 3; $i++) {
            // One is already stored, so three more makes four — over the new
            // ceiling of three. This is the point of the test: the *existing*
            // cache must not survive the write, or the ceiling would still read
            // as ten.
            $files[] = $this->tinyJpeg("more{$i}.jpg");
        }

        app('auth')->forgetGuards();

        $this->upload($listing, $files)
            ->assertStatus(422)
            ->assertJsonValidationErrors('photos');
    }

    // --------------------------------------------------------------- deletion

    #[Test]
    public function a_photo_can_be_deleted_by_the_url_it_was_served(): void
    {
        $listing = $this->createListing($this->seller);

        $served = $this->upload($listing, [$this->tinyJpeg('front.jpg')])
            ->assertStatus(201)
            ->json('data.photos');

        $filename = $this->storedPhotos($listing)[0];

        // The client holds a URL, not a filename — deletion accepts the value
        // it was actually served.
        $this->removePhoto($listing, $served[0])
            ->assertOk()
            ->assertJsonPath('data.photos', []);

        $this->assertSame([], $this->storedPhotos($listing));
        Storage::disk(Listing::PHOTO_DISK)->assertMissing($listing->id.'/'.$filename);
    }

    #[Test]
    public function a_photo_can_be_deleted_by_filename(): void
    {
        $listing = $this->createListing($this->seller, ['photos' => ['keep.jpg', 'drop.jpg']]);

        $this->removePhoto($listing, 'drop.jpg')
            ->assertOk()
            ->assertJsonCount(1, 'data.photos');

        $this->assertSame(['keep.jpg'], $this->storedPhotos($listing));
    }

    #[Test]
    public function deleting_a_photo_that_is_not_on_the_listing_is_404(): void
    {
        $listing = $this->createListing($this->seller, ['photos' => ['front.jpg']]);

        $this->removePhoto($listing, 'never-existed.jpg')->assertNotFound();
    }

    #[Test]
    public function the_last_photo_of_an_active_listing_cannot_be_removed(): void
    {
        $listing = $this->createListing($this->seller, [
            'status' => ListingStatus::Active,
            'photos' => ['only.jpg'],
        ]);
        $this->writePhotoFiles($listing, ['only.jpg']);

        $this->removePhoto($listing, 'only.jpg')->assertStatus(409);

        $this->assertSame(['only.jpg'], $this->storedPhotos($listing));
        Storage::disk(Listing::PHOTO_DISK)->assertExists($listing->id.'/only.jpg');
    }

    #[Test]
    public function a_non_final_photo_of_an_active_listing_can_be_removed(): void
    {
        $listing = $this->createListing($this->seller, [
            'status' => ListingStatus::Active,
            'photos' => ['keep.jpg', 'drop.jpg'],
        ]);
        $this->writePhotoFiles($listing, ['keep.jpg', 'drop.jpg']);

        $this->removePhoto($listing, 'drop.jpg')
            ->assertOk()
            ->assertJsonCount(1, 'data.photos');

        $this->assertSame(['keep.jpg'], $this->storedPhotos($listing));
        Storage::disk(Listing::PHOTO_DISK)->assertMissing($listing->id.'/drop.jpg');
        Storage::disk(Listing::PHOTO_DISK)->assertExists($listing->id.'/keep.jpg');
    }

    #[Test]
    public function the_last_photo_of_a_draft_can_be_removed(): void
    {
        // Only the published state is guarded: a draft may be photo-less until
        // it is submitted.
        $listing = $this->createListing($this->seller, ['photos' => ['only.jpg']]);
        $this->writePhotoFiles($listing, ['only.jpg']);

        $this->removePhoto($listing, 'only.jpg')
            ->assertOk()
            ->assertJsonPath('data.photos', []);
    }

    // -------------------------------------------------- ownership and access

    /**
     * Both photo routes, as a method/URI pair, so the access rules are
     * asserted for every row rather than assumed from one.
     *
     * @return array<string, array{string, string}>
     */
    public static function photoRoutes(): array
    {
        return [
            'upload' => ['POST', '/api/seller/listings/{listing}/photos'],
            'delete' => ['DELETE', '/api/seller/listings/{listing}/photos'],
        ];
    }

    /**
     * A body that is valid for the given route, so a refusal can only be about
     * who is calling — an invalid body on the upload route would be a 422
     * before ownership is ever consulted.
     *
     * @return array<int, mixed>
     */
    private function validBodyFor(string $method): array
    {
        return $method === 'POST'
            ? ['photos' => [$this->tinyJpeg('front.jpg')]]
            : ['photo' => 'front.jpg'];
    }

    #[Test]
    #[DataProvider('photoRoutes')]
    public function another_seller_gets_404_not_403(string $method, string $uri): void
    {
        $listing = $this->createListing($this->seller, ['photos' => ['front.jpg']]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->otherSeller))
            ->$method(str_replace('{listing}', (string) $listing->id, $uri), $this->validBodyFor($method))
            ->assertNotFound();

        // The listing is untouched — and a 403 here would have told a
        // stranger that the id exists.
        $this->assertSame(['front.jpg'], $this->storedPhotos($listing));
    }

    #[Test]
    #[DataProvider('photoRoutes')]
    public function a_buyer_is_refused_by_the_capability_gate(string $method, string $uri): void
    {
        $listing = $this->createListing($this->seller, ['photos' => ['front.jpg']]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->buyer))
            ->$method(str_replace('{listing}', (string) $listing->id, $uri), $this->validBodyFor($method))
            ->assertForbidden();
    }

    #[Test]
    #[DataProvider('photoRoutes')]
    public function an_unauthenticated_request_is_refused(string $method, string $uri): void
    {
        $listing = $this->createListing($this->seller);

        $this->$method(str_replace('{listing}', (string) $listing->id, $uri), $this->validBodyFor($method))
            ->assertUnauthorized();
    }

    #[Test]
    public function photos_cannot_be_changed_while_the_listing_is_under_review(): void
    {
        $listing = $this->createListing($this->seller, [
            'status' => ListingStatus::Pending,
            'photos' => ['front.jpg'],
        ]);

        // Photos are content, and content is frozen mid-review [D-24] — the
        // upload endpoint must not be a way around the PATCH restriction.
        $this->upload($listing, [$this->tinyJpeg('sneaky.jpg')])
            ->assertStatus(409);

        $this->removePhoto($listing, 'front.jpg')->assertStatus(409);

        $this->assertSame(['front.jpg'], $this->storedPhotos($listing));
    }

    // -------------------------------------------------------- representation

    #[Test]
    public function the_model_stores_filenames_and_serves_urls(): void
    {
        // All three client shapes — relative path, full URL, bare filename —
        // collapse to the same stored form.
        $listing = $this->createListing($this->seller, [
            'photos' => [
                'listings/5/front.jpg',
                'http://localhost:8001/storage/listings/5/side.jpg',
                'cow.png',
            ],
        ]);

        $this->assertSame(
            ['front.jpg', 'side.jpg', 'cow.png'],
            $this->storedPhotos($listing),
        );

        $this->assertSame(
            [
                $this->photoBase().'/'.$listing->id.'/front.jpg',
                $this->photoBase().'/'.$listing->id.'/side.jpg',
                $this->photoBase().'/'.$listing->id.'/cow.png',
            ],
            $listing->photos,
        );
    }

    #[Test]
    public function malformed_photo_entries_never_reach_storage_or_a_client(): void
    {
        // The write contract is a list of strings. The model drops the rest at
        // the column, so no path can surface a shape a client must defend
        // against.
        $listing = $this->createListing($this->seller, [
            'photos' => ['front.jpg', 42, null, ['url' => 'nope']],
        ]);

        $this->assertSame(['front.jpg'], $this->storedPhotos($listing));

        $this->assertSame(
            [$this->photoBase().'/'.$listing->id.'/front.jpg'],
            $listing->photos,
        );
    }

    #[Test]
    public function photos_are_served_as_urls_on_the_marketplace(): void
    {
        $listing = $this->createListing($this->seller, [
            'status' => ListingStatus::Active,
            'photos' => ['front.jpg'],
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken(User::factory()->create()))
            ->getJson("/api/listings/{$listing->id}")
            ->assertOk()
            ->assertJsonPath('data.photos', [
                $this->photoBase().'/'.$listing->id.'/front.jpg',
            ]);
    }

    // --------------------------------------------------------------- audit log

    #[Test]
    public function adding_photos_records_an_activity(): void
    {
        $listing = $this->createListing($this->seller);

        $this->upload($listing, [
            $this->tinyJpeg('front.jpg'),
            $this->tinyPng('side.png'),
        ])->assertStatus(201);

        // Exactly one entry: an upload writes one audit row, not one per file.
        $activity = Activity::query()->sole();

        $this->assertSame('listing_photo_added', $activity->action);
        $this->assertSame($this->seller->id, $activity->user_id);
        $this->assertNotNull($activity->created_at);
        $this->assertSame('listing', $activity->metadata['target_type']);
        $this->assertSame($listing->id, $activity->metadata['target_id']);
        $this->assertSame(['from' => 0, 'to' => 2], $activity->metadata['changes']['photos']);
    }

    #[Test]
    public function the_activity_records_the_running_photo_count(): void
    {
        $listing = $this->createListing($this->seller, ['photos' => ['a.jpg', 'b.jpg']]);

        $this->upload($listing, [$this->tinyJpeg('c.jpg')])->assertStatus(201);

        $activity = Activity::query()->sole();

        $this->assertSame(['from' => 2, 'to' => 3], $activity->metadata['changes']['photos']);
    }

    #[Test]
    public function a_rejected_upload_records_no_activity(): void
    {
        // Nine stored, so two more pass the per-request ceiling but break the
        // service's cumulative one — the refusal happens before any write.
        $listing = $this->createListing($this->seller, [
            'photos' => ['a.jpg', 'b.jpg', 'c.jpg', 'd.jpg', 'e.jpg', 'f.jpg', 'g.jpg', 'h.jpg', 'i.jpg'],
        ]);

        $this->upload($listing, [
            $this->tinyJpeg('one.jpg'),
            $this->tinyJpeg('two.jpg'),
        ])->assertStatus(422)->assertJsonValidationErrors('photos');

        $this->assertSame(0, Activity::query()->count());
    }

    #[Test]
    public function an_upload_under_review_records_no_activity(): void
    {
        $listing = $this->createListing($this->seller, [
            'status' => ListingStatus::Pending,
            'photos' => ['front.jpg'],
        ]);

        $this->upload($listing, [$this->tinyJpeg('sneaky.jpg')])->assertStatus(409);

        $this->assertSame(0, Activity::query()->count());
    }

    #[Test]
    public function a_failed_write_records_no_activity(): void
    {
        $listing = $this->createListing($this->seller);

        // The disk reports a failed write, so the service throws before it can
        // update the row or reach the audit write.
        $disk = \Mockery::mock(Filesystem::class);
        $disk->shouldReceive('putFileAs')->once()->andReturn(false);
        Storage::shouldReceive('disk')->with(Listing::PHOTO_DISK)->andReturn($disk);

        try {
            app(SellerListingService::class)->addPhotos($listing, [$this->tinyJpeg('front.jpg')]);
            $this->fail('A failed photo write must throw.');
        } catch (\RuntimeException) {
            // Expected: the write failure aborts the operation.
        }

        $this->assertSame(0, Activity::query()->count());
    }
}
