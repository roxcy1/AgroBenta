<?php

namespace Tests\Feature\SellerListing;

use App\Enums\ListingStatus;
use App\Enums\UserRole;
use App\Models\Listing;
use App\Models\Setting;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Illuminate\Testing\TestResponse;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Seller listing management — contract §5.4.
 *
 * The lifecycle is the point of this file. A seller may create a draft, submit
 * it, edit a draft or an active listing, and delete a draft or a withdrawn one.
 * Everything else — publishing, deactivating, marking sold, or reaching another
 * seller's row — is refused, and each refusal is asserted rather than assumed:
 * this is the surface where "the client just won't offer that button" is not a
 * security property.
 */
class MobileSellerListingTest extends TestCase
{
    use RefreshDatabase;

    private User $seller;

    private User $otherSeller;

    private User $buyer;

    protected function setUp(): void
    {
        parent::setUp();

        // Submission now compares the stored filenames with the disk, so the
        // suite needs a real (faked) disk rather than a name with no file.
        Storage::fake(Listing::PHOTO_DISK);

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

    private function mobileToken(User $user): string
    {
        return $user->createToken('mobile', ['mobile'])->plainTextToken;
    }

    /**
     * @param  array<string, mixed>  $overrides
     * @param  bool  $writePhotoFiles  When false, the stored filenames are left
     *                                 without files, to model a row whose
     *                                 storage was lost or never written.
     */
    private function createListing(User $seller, array $overrides = [], bool $writePhotoFiles = true): Listing
    {
        $listing = Listing::create(array_merge([
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
            // A stored photo by default, because submission requires one
            // [DEC-03]. Tests about the photo rule override this with `[]`.
            'photos' => ['submitted-photo.jpg'],
            'status' => ListingStatus::Draft,
        ], $overrides));

        if ($writePhotoFiles) {
            $disk = Storage::disk(Listing::PHOTO_DISK);

            foreach ($listing->storedPhotoFilenames() as $filename) {
                $disk->put($listing->id.'/'.$filename, 'photo');
            }
        }

        return $listing;
    }

    /**
     * @param  array<string, mixed>  $body
     */
    private function store(array $body = [], ?string $token = null): TestResponse
    {
        return $this->withHeader(
            'Authorization',
            'Bearer '.($token ?? $this->mobileToken($this->seller)),
        )->postJson('/api/seller/listings', array_merge([
            'livestock_type' => 'cattle',
            'location' => 'Bukidnon',
            'asking_price' => 50000,
            'quantity' => 3,
        ], $body));
    }

    // ---------------------------------------------------------------- access

    /**
     * Every route in the seller group, as a method/URI pair.
     *
     * A provider rather than two hand-picked calls: the capability gate must
     * refuse all five routes before any controller or Form Request logic runs,
     * and "the middleware is on the group" is an assumption until every row has
     * been asserted.
     *
     * @return array<string, array{string, string}>
     */
    public static function sellerRoutes(): array
    {
        return [
            'index' => ['GET', '/api/seller/listings'],
            'store' => ['POST', '/api/seller/listings'],
            'update' => ['PATCH', '/api/seller/listings/{listing}'],
            'submit' => ['POST', '/api/seller/listings/{listing}/submit'],
            'destroy' => ['DELETE', '/api/seller/listings/{listing}'],
        ];
    }

    #[Test]
    #[DataProvider('sellerRoutes')]
    public function a_buyer_cannot_manage_listings(string $method, string $uri): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Draft]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->buyer))
            ->json($method, str_replace('{listing}', (string) $listing->id, $uri))
            ->assertForbidden();
    }

    #[Test]
    public function an_unauthenticated_request_is_rejected(): void
    {
        $this->getJson('/api/seller/listings')->assertUnauthorized();
    }

    #[Test]
    public function an_admin_token_cannot_reach_the_seller_api(): void
    {
        $admin = User::factory()->admin()->create();
        $token = $admin->createToken('admin', ['admin'])->plainTextToken;

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->getJson('/api/seller/listings')
            ->assertForbidden();
    }

    // ---------------------------------------------------------------- create

    #[Test]
    public function a_seller_creates_a_draft(): void
    {
        $response = $this->store([
            'livestock_type' => 'goat',
            'breed' => 'Boer',
            'age_value' => 8,
            'age_unit' => 'month',
            'gender' => 'female',
            'weight_value' => 32.5,
            'weight_unit' => 'kg',
            'health_status' => 'healthy',
            'short_description' => 'Boer does, ready for sale',
        ]);

        $response->assertCreated()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.status', ListingStatus::Draft->value)
            ->assertJsonPath('data.livestock_type', 'goat')
            ->assertJsonPath('data.quantity', 3)
            ->assertJsonPath('data.photos', []);

        $this->assertDatabaseHas('listings', [
            'livestock_type' => 'goat',
            'seller_id' => $this->seller->id,
            'status' => ListingStatus::Draft->value,
        ]);
    }

    #[Test]
    public function a_created_listing_belongs_to_the_authenticated_seller(): void
    {
        $this->store([], $this->mobileToken($this->otherSeller));

        $this->assertDatabaseHas('listings', ['seller_id' => $this->otherSeller->id]);
        $this->assertDatabaseMissing('listings', ['seller_id' => $this->seller->id]);
    }

    #[Test]
    public function a_seller_cannot_choose_the_status(): void
    {
        $this->store(['status' => 'active'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('status');

        $this->assertDatabaseCount('listings', 0);
    }

    #[Test]
    public function a_seller_cannot_choose_the_owner(): void
    {
        $this->store(['seller_id' => $this->otherSeller->id])
            ->assertStatus(422)
            ->assertJsonValidationErrors('seller_id');

        $this->assertDatabaseCount('listings', 0);
    }

    #[Test]
    public function the_four_required_fields_are_required(): void
    {
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings', [])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['livestock_type', 'location', 'asking_price', 'quantity']);
    }

    #[Test]
    public function a_half_supplied_value_and_unit_pair_is_rejected(): void
    {
        $this->store(['age_value' => 8])
            ->assertStatus(422)
            ->assertJsonValidationErrors('age_unit');

        $this->store(['weight_unit' => 'kg'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('weight_value');
    }

    #[Test]
    public function numeric_fields_are_validated(): void
    {
        $this->store(['asking_price' => 'not-a-price', 'quantity' => 0])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['asking_price', 'quantity']);
    }

    #[Test]
    public function the_asking_price_ceiling_follows_the_setting(): void
    {
        Setting::create([
            'key' => 'listing.max_price',
            'value' => '10000',
            'group' => 'listings',
            'label' => 'Maximum Asking Price',
            'description' => 'The highest asking price a listing may be given.',
        ]);

        $this->store(['asking_price' => 10001])
            ->assertStatus(422)
            ->assertJsonValidationErrors('asking_price');

        $this->store(['asking_price' => 10000])
            ->assertStatus(201);
    }

    #[Test]
    public function a_malformed_asking_price_ceiling_falls_back_to_the_column_maximum(): void
    {
        // Garbage in the setting must not switch off the bound: the code's own
        // `decimal(14,2)` ceiling still rejects an over-range price.
        Setting::create([
            'key' => 'listing.max_price',
            'value' => 'not-a-number',
            'group' => 'listings',
            'label' => 'Maximum Asking Price',
            'description' => 'The highest asking price a listing may be given.',
        ]);

        $this->store(['asking_price' => '100000000000.00'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('asking_price');
    }

    /**
     * A stored ceiling outside the registry bounds falls back to the column
     * maximum, exactly as garbage does — never to itself.
     *
     * Written straight to the table because the admin API refuses these values;
     * the point is the *consumer's* defence. Both directions are asserted: a
     * ceiling of `0` must not reject every price, and the fallback must still be
     * a real ceiling that an over-range price fails.
     */
    #[Test]
    #[DataProvider('outOfBoundsAskingPriceCeilings')]
    public function an_out_of_bounds_asking_price_ceiling_falls_back_to_the_column_maximum(string $setting): void
    {
        Setting::create([
            'key' => 'listing.max_price',
            'value' => $setting,
            'group' => 'listings',
            'label' => 'Maximum Asking Price',
            'description' => 'The highest asking price a listing may be given.',
        ]);

        $this->store(['asking_price' => 50000])->assertStatus(201);

        $this->store(['asking_price' => '100000000000.00'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('asking_price');
    }

    /**
     * @return array<string, array{string}>
     */
    public static function outOfBoundsAskingPriceCeilings(): array
    {
        return [
            'zero' => ['0'],
            'negative' => ['-10'],
            'above the registry maximum' => ['100000000000.00'],
        ];
    }

    #[Test]
    public function the_age_value_is_validated_as_an_integer(): void
    {
        // The column is `decimal(5,1)`, but the contract says `integer`, and the
        // contract is what a client is held to. Asserted explicitly so that
        // loosening the rule to match the column cannot pass unnoticed.
        $this->store(['age_value' => 8.5, 'age_unit' => 'month'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('age_value');
    }

    /**
     * The approved unit-aware age ceilings [DEC-01], as boundary and one above.
     *
     * @return array<string, array{string, int, int}>
     */
    public static function ageLimits(): array
    {
        return [
            'days' => ['day', 9125, 9126],
            'months' => ['month', 300, 301],
            'years' => ['year', 25, 26],
        ];
    }

    #[Test]
    #[DataProvider('ageLimits')]
    public function the_age_maximum_depends_on_the_selected_unit(string $unit, int $maximum, int $aboveMaximum): void
    {
        // The boundary is accepted in each unit. A unit-blind `max:25` would
        // reject 9,125 days and 300 months, so these assertions also prove the
        // value is not converted to another unit first.
        $this->store(['age_value' => $maximum, 'age_unit' => $unit])->assertCreated();

        $this->store(['age_value' => $aboveMaximum, 'age_unit' => $unit])
            ->assertStatus(422)
            ->assertJsonValidationErrors('age_value');

        $this->assertDatabaseCount('listings', 1);
    }

    #[Test]
    #[DataProvider('ageLimits')]
    public function the_age_maximum_depends_on_the_selected_unit_on_update(string $unit, int $maximum, int $aboveMaximum): void
    {
        $listing = $this->createListing($this->seller, [
            'age_value' => null,
            'age_unit' => null,
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, [
                'age_value' => $maximum,
                'age_unit' => $unit,
            ])
            ->assertOk();

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, [
                'age_value' => $aboveMaximum,
                'age_unit' => $unit,
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('age_value');
    }

    #[Test]
    public function a_third_decimal_place_is_rejected_on_create(): void
    {
        // DEC-02: the value is rejected rather than silently rounded by the
        // decimal column, so what the seller typed is what would be stored.
        $this->store([
            'asking_price' => 50000.123,
            'weight_value' => 320.555,
            'weight_unit' => 'kg',
        ])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['asking_price', 'weight_value']);

        $this->assertDatabaseCount('listings', 0);
    }

    #[Test]
    public function two_decimal_places_are_accepted_on_create(): void
    {
        $this->store([
            'asking_price' => 50000.12,
            'weight_value' => 320.55,
            'weight_unit' => 'kg',
        ])->assertCreated();

        $this->assertDatabaseCount('listings', 1);
    }

    #[Test]
    public function a_third_decimal_place_is_rejected_on_update(): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Draft]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, [
                'asking_price' => 50000.123,
                'weight_value' => 320.555,
                'weight_unit' => 'kg',
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['asking_price', 'weight_value']);

        // Refused, not stored: the row keeps the values it already had.
        $stored = Listing::query()->findOrFail($listing->id);

        $this->assertSame('50000.00', $stored->asking_price);
        $this->assertSame('500.00', $stored->weight_value);
    }

    #[Test]
    public function a_non_string_photo_entry_is_rejected(): void
    {
        // The stored representation is still undecided (D-10), so this asserts
        // only what is already known: whatever the array holds, it is strings.
        $this->store(['photos' => [123]])
            ->assertStatus(422)
            ->assertJsonValidationErrors('photos.0');
    }

    #[Test]
    public function a_listing_cannot_be_created_with_photos(): void
    {
        // A listing that does not exist yet has no directory to scope a
        // filename to, so a photo can only be attached through the upload
        // endpoint after the draft is saved.
        $this->store(['photos' => ['smuggled.jpg']])
            ->assertStatus(422)
            ->assertJsonValidationErrors('photos');

        $this->assertDatabaseCount('listings', 0);
    }

    #[Test]
    public function a_draft_can_be_created_without_photos(): void
    {
        // Photo-optional drafting is the other half of the rule: no photos is
        // valid, an absent key is valid, and only a non-empty list is refused.
        $this->store(['photos' => []])
            ->assertCreated()
            ->assertJsonPath('data.photos', []);

        $this->store()
            ->assertCreated()
            ->assertJsonPath('data.photos', []);
    }

    // ------------------------------------------------------------------- read

    #[Test]
    public function a_seller_sees_their_own_listings_in_every_status(): void
    {
        foreach (ListingStatus::cases() as $status) {
            $this->createListing($this->seller, ['status' => $status]);
        }

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->getJson('/api/seller/listings')
            ->assertOk()
            ->assertJsonPath('data.pagination.total', count(ListingStatus::cases()));
    }

    #[Test]
    public function a_seller_does_not_see_another_sellers_listings(): void
    {
        $this->createListing($this->otherSeller, ['status' => ListingStatus::Active]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->getJson('/api/seller/listings')
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 0)
            ->assertJsonPath('data.listings', []);
    }

    #[Test]
    public function a_seller_may_filter_their_own_listings_by_status(): void
    {
        $this->createListing($this->seller, ['status' => ListingStatus::Draft]);
        $this->createListing($this->seller, ['status' => ListingStatus::Active]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->getJson('/api/seller/listings?status=draft')
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 1)
            ->assertJsonPath('data.listings.0.status', ListingStatus::Draft->value);
    }

    #[Test]
    public function an_unknown_status_filter_is_rejected(): void
    {
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->getJson('/api/seller/listings?status=published')
            ->assertStatus(422)
            ->assertJsonValidationErrors('status');
    }

    #[Test]
    public function a_seller_cannot_filter_by_seller_id(): void
    {
        $this->createListing($this->otherSeller, ['status' => ListingStatus::Active]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->getJson('/api/seller/listings?seller_id='.$this->otherSeller->id)
            ->assertStatus(422)
            ->assertJsonValidationErrors('seller_id');
    }

    #[Test]
    public function a_seller_may_search_their_own_listings(): void
    {
        $this->createListing($this->seller, ['livestock_type' => 'cattle']);
        $this->createListing($this->seller, ['livestock_type' => 'goat', 'location' => 'Davao']);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->getJson('/api/seller/listings?search=goat')
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 1)
            ->assertJsonPath('data.listings.0.livestock_type', 'goat');
    }

    #[Test]
    public function a_seller_listing_pagination(): void
    {
        foreach (range(1, 20) as $index) {
            $this->createListing($this->seller, ['livestock_type' => 'cattle '.$index]);
        }

        $response = $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->getJson('/api/seller/listings?page=2&per_page=5');

        $response->assertOk()
            ->assertJsonCount(5, 'data.listings')
            ->assertJsonPath('data.pagination.current_page', 2)
            ->assertJsonPath('data.pagination.last_page', 4)
            ->assertJsonPath('data.pagination.per_page', 5)
            ->assertJsonPath('data.pagination.total', 20);
    }

    #[Test]
    public function the_seller_listing_response_carries_no_internal_fields(): void
    {
        $this->createListing($this->seller, ['status' => ListingStatus::Draft]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->getJson('/api/seller/listings')
            ->assertOk()
            ->assertJsonPath('data.listings.0.seller.email', null)
            ->assertJsonPath('data.listings.0.seller.name', 'Juan Dela Cruz')
            ->assertJsonMissingPath('data.listings.0.user_id');
    }

    // ---------------------------------------------------------------- update

    #[Test]
    public function a_draft_can_be_edited(): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Draft]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, [
                'asking_price' => 62500,
                'breed' => 'Hereford',
            ])
            ->assertOk()
            ->assertJsonPath('data.asking_price', '62500.00')
            ->assertJsonPath('data.breed', 'Hereford')
            // Untouched fields stay untouched: this is a PATCH, not a replace.
            ->assertJsonPath('data.location', 'Bukidnon');
    }

    #[Test]
    public function an_active_listing_can_be_edited(): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Active]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, ['quantity' => 7])
            ->assertOk()
            ->assertJsonPath('data.quantity', 7);
    }

    #[Test]
    public function a_partial_update_does_not_demand_the_required_fields(): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Draft]);

        // A seller correcting one field must not receive errors about the three
        // they never touched. This is the assertion that catches a `required`
        // rule left in place on the PATCH path.
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, ['breed' => 'Hereford'])
            ->assertOk()
            ->assertJsonPath('data.breed', 'Hereford')
            ->assertJsonPath('data.livestock_type', 'cattle')
            ->assertJsonPath('data.asking_price', '50000.00');
    }

    #[Test]
    public function a_partial_update_can_leave_a_value_and_unit_pair_incomplete(): void
    {
        // Starts with no age recorded at all, so supplying only the value below is
        // what leaves the pair half-filled.
        $listing = $this->createListing($this->seller, [
            'status' => ListingStatus::Draft,
            'age_value' => null,
            'age_unit' => null,
        ]);

        // `age_value` and `age_unit` are both nullable columns, and `sometimes`
        // disables `required_with`, so a partial update is allowed to leave the
        // pair half-supplied. That is the contract's own consequence rather than a
        // gap in it — and the pair is not left unchecked. See the submit step
        // below: a listing in this state cannot be submitted.
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, ['age_value' => 30])
            ->assertOk()
            // The unit is the point of this assertion. `age_value` is deliberately
            // not asserted by value: the model's `decimal:1` cast reads it back
            // as the string "30.0", which the mobile model already handles.
            ->assertJsonPath('data.age_unit', null);

        // The pair invariant is enforced where the contract says it is: a listing
        // must satisfy the create rules to be submitted, so this one is refused
        // rather than queued for a moderator to read.
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings/'.$listing->id.'/submit')
            ->assertStatus(422)
            ->assertJsonValidationErrors('age_unit');
    }

    /**
     * @return array<string, array{ListingStatus}>
     */
    public static function nonEditableStatuses(): array
    {
        return [
            'pending' => [ListingStatus::Pending],
            'sold' => [ListingStatus::Sold],
            'inactive' => [ListingStatus::Inactive],
        ];
    }

    #[Test]
    #[DataProvider('nonEditableStatuses')]
    public function a_listing_in_a_locked_status_cannot_be_edited(ListingStatus $status): void
    {
        $listing = $this->createListing($this->seller, ['status' => $status]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, ['quantity' => 9])
            ->assertStatus(409);
    }

    #[Test]
    public function an_edit_cannot_change_the_status(): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Draft]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, ['status' => 'active'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('status');

        $this->assertDatabaseHas('listings', [
            'id' => $listing->id,
            'status' => ListingStatus::Draft->value,
        ]);
    }

    #[Test]
    public function a_seller_cannot_edit_another_sellers_listing(): void
    {
        $listing = $this->createListing($this->otherSeller, ['status' => ListingStatus::Draft]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, ['quantity' => 9])
            ->assertNotFound();

        $this->assertDatabaseHas('listings', ['id' => $listing->id, 'quantity' => 1]);
    }

    // ---------------------------------------------------------------- submit

    #[Test]
    public function a_draft_can_be_submitted_for_review(): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Draft]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings/'.$listing->id.'/submit')
            ->assertOk()
            ->assertJsonPath('data.status', ListingStatus::Pending->value)
            // A stored photo is what makes the draft submittable [DEC-03], and
            // it survives the transition unchanged.
            ->assertJsonCount(1, 'data.photos');

        $this->assertDatabaseHas('listings', [
            'id' => $listing->id,
            'status' => ListingStatus::Pending->value,
        ]);
    }

    #[Test]
    public function a_draft_without_a_stored_photo_cannot_be_submitted_for_review(): void
    {
        // A draft may be saved with no photos (§4.5), but it cannot enter
        // review until at least one is stored [DEC-03].
        $listing = $this->createListing($this->seller, [
            'status' => ListingStatus::Draft,
            'photos' => [],
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings/'.$listing->id.'/submit')
            ->assertStatus(422)
            ->assertJsonValidationErrors('photos');

        $this->assertDatabaseHas('listings', [
            'id' => $listing->id,
            'status' => ListingStatus::Draft->value,
        ]);
    }

    #[Test]
    public function a_draft_whose_stored_photo_file_is_missing_cannot_be_submitted_for_review(): void
    {
        // The column names a photo, but no file was ever written. Without this
        // check the draft could be queued and approved on a broken image.
        $listing = $this->createListing(
            $this->seller,
            ['status' => ListingStatus::Draft],
            writePhotoFiles: false,
        );

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings/'.$listing->id.'/submit')
            ->assertStatus(422)
            ->assertJsonValidationErrors('photos');

        $this->assertDatabaseHas('listings', [
            'id' => $listing->id,
            'status' => ListingStatus::Draft->value,
        ]);
    }

    #[Test]
    #[DataProvider('ageLimits')]
    public function a_draft_whose_age_exceeds_the_unit_maximum_cannot_be_submitted(string $unit, int $maximum, int $aboveMaximum): void
    {
        // A draft written before the limit existed, or outside this API, is
        // caught at the last gate rather than queued for a moderator.
        $listing = $this->createListing($this->seller, [
            'status' => ListingStatus::Draft,
            'age_value' => $aboveMaximum,
            'age_unit' => $unit,
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings/'.$listing->id.'/submit')
            ->assertStatus(422)
            ->assertJsonValidationErrors('age_value');

        $this->assertDatabaseHas('listings', [
            'id' => $listing->id,
            'status' => ListingStatus::Draft->value,
        ]);
    }

    #[Test]
    #[DataProvider('ageLimits')]
    public function a_draft_at_the_age_maximum_can_be_submitted(string $unit, int $maximum, int $aboveMaximum): void
    {
        $listing = $this->createListing($this->seller, [
            'status' => ListingStatus::Draft,
            'age_value' => $maximum,
            'age_unit' => $unit,
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings/'.$listing->id.'/submit')
            ->assertOk()
            ->assertJsonPath('data.status', ListingStatus::Pending->value);
    }

    #[Test]
    public function a_draft_with_more_than_two_decimal_places_cannot_be_submitted(): void
    {
        // Create and update already refuse a third decimal, so this models a row
        // written outside the API or before the rule existed. Submission is the
        // last gate, and it must see the stored value rather than the rounded
        // `decimal:2` cast.
        $listing = $this->createListing($this->seller, [
            'status' => ListingStatus::Draft,
            'asking_price' => 50000.123,
            'weight_value' => 320.555,
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings/'.$listing->id.'/submit')
            ->assertStatus(422)
            ->assertJsonValidationErrors(['asking_price', 'weight_value']);

        $this->assertDatabaseHas('listings', [
            'id' => $listing->id,
            'status' => ListingStatus::Draft->value,
        ]);
    }

    #[Test]
    public function a_draft_at_the_maximum_precision_can_be_submitted(): void
    {
        $listing = $this->createListing($this->seller, [
            'status' => ListingStatus::Draft,
            'asking_price' => 50000.12,
            'weight_value' => 320.55,
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings/'.$listing->id.'/submit')
            ->assertOk()
            ->assertJsonPath('data.status', ListingStatus::Pending->value);
    }

    #[Test]
    public function a_pending_listing_cannot_be_submitted_again(): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Pending]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings/'.$listing->id.'/submit')
            ->assertStatus(409);

        $this->assertDatabaseHas('listings', [
            'id' => $listing->id,
            'status' => ListingStatus::Pending->value,
        ]);
    }

    #[Test]
    public function a_seller_cannot_submit_an_active_listing(): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Active]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings/'.$listing->id.'/submit')
            ->assertStatus(409);
    }

    #[Test]
    public function a_seller_cannot_submit_another_sellers_draft(): void
    {
        $listing = $this->createListing($this->otherSeller, ['status' => ListingStatus::Draft]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings/'.$listing->id.'/submit')
            ->assertNotFound();

        $this->assertDatabaseHas('listings', [
            'id' => $listing->id,
            'status' => ListingStatus::Draft->value,
        ]);
    }

    #[Test]
    public function an_invalid_draft_is_not_queued_for_review(): void
    {
        // A row that could not be created through the API: the contract requires
        // a listing to satisfy the create rules at the moment it is submitted, so
        // it is rejected here rather than handed to a moderator broken.
        $listing = $this->createListing($this->seller, [
            'status' => ListingStatus::Draft,
            'quantity' => 0,
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings/'.$listing->id.'/submit')
            ->assertStatus(422)
            ->assertJsonValidationErrors('quantity');

        $this->assertDatabaseHas('listings', [
            'id' => $listing->id,
            'status' => ListingStatus::Draft->value,
        ]);
    }

    #[Test]
    public function a_submit_cannot_carry_a_status(): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Draft]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings/'.$listing->id.'/submit', ['status' => 'active'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('status');

        $this->assertDatabaseHas('listings', [
            'id' => $listing->id,
            'status' => ListingStatus::Draft->value,
        ]);
    }

    #[Test]
    public function a_submit_cannot_carry_a_seller_id(): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Draft]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings/'.$listing->id.'/submit', [
                'seller_id' => $this->otherSeller->id,
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('seller_id');

        $this->assertDatabaseHas('listings', [
            'id' => $listing->id,
            'status' => ListingStatus::Draft->value,
        ]);
    }

    #[Test]
    public function a_submit_rejects_any_body_field_because_its_allow_list_is_empty(): void
    {
        // Contract §6.2: the client may set *none* and every field present is
        // rejected — not just the two dangerous names. A body on this route is
        // a client bug whichever key it carries, and silently dropping it is
        // what the security rule forbids.
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Draft]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings/'.$listing->id.'/submit', ['breed' => 'Angus'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('breed');

        $this->assertDatabaseHas('listings', [
            'id' => $listing->id,
            'status' => ListingStatus::Draft->value,
        ]);
    }

    // ---------------------------------------------------------------- delete

    #[Test]
    public function a_delete_cannot_carry_a_status_or_seller_id(): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Draft]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->deleteJson('/api/seller/listings/'.$listing->id, ['status' => 'inactive'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('status');

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->deleteJson('/api/seller/listings/'.$listing->id, [
                'seller_id' => $this->otherSeller->id,
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('seller_id');

        // Rejected, not applied: both refusals happened before the controller,
        // so the draft is still there, still the caller's.
        $this->assertDatabaseHas('listings', [
            'id' => $listing->id,
            'seller_id' => $this->seller->id,
            'status' => ListingStatus::Draft->value,
        ]);
    }

    #[Test]
    public function a_draft_can_be_deleted(): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Draft]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->deleteJson('/api/seller/listings/'.$listing->id)
            ->assertOk()
            ->assertJsonPath('success', true);

        $this->assertDatabaseMissing('listings', ['id' => $listing->id]);
    }

    #[Test]
    public function an_inactive_listing_can_be_deleted(): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Inactive]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->deleteJson('/api/seller/listings/'.$listing->id)
            ->assertOk();

        $this->assertDatabaseMissing('listings', ['id' => $listing->id]);
    }

    /**
     * @return array<string, array{ListingStatus}>
     */
    public static function nonDeletableStatuses(): array
    {
        return [
            'pending' => [ListingStatus::Pending],
            'active' => [ListingStatus::Active],
            'sold' => [ListingStatus::Sold],
        ];
    }

    #[Test]
    #[DataProvider('nonDeletableStatuses')]
    public function a_live_listing_cannot_be_deleted(ListingStatus $status): void
    {
        $listing = $this->createListing($this->seller, ['status' => $status]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->deleteJson('/api/seller/listings/'.$listing->id)
            ->assertStatus(409);

        $this->assertDatabaseHas('listings', ['id' => $listing->id]);
    }

    #[Test]
    public function a_seller_cannot_delete_another_sellers_listing(): void
    {
        $listing = $this->createListing($this->otherSeller, ['status' => ListingStatus::Draft]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->deleteJson('/api/seller/listings/'.$listing->id)
            ->assertNotFound();

        $this->assertDatabaseHas('listings', ['id' => $listing->id]);
    }

    #[Test]
    public function a_missing_listing_is_a_404(): void
    {
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/999999', ['quantity' => 2])
            ->assertNotFound();
    }

    // ------------------------------------------------------------ visibility

    #[Test]
    public function a_draft_is_absent_from_the_marketplace_browse(): void
    {
        $this->createListing($this->seller, ['status' => ListingStatus::Draft]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->buyer))
            ->getJson('/api/listings')
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 0);
    }

    #[Test]
    public function a_pending_listing_is_absent_from_the_marketplace_browse(): void
    {
        $this->createListing($this->seller, ['status' => ListingStatus::Pending]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->buyer))
            ->getJson('/api/listings')
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 0);
    }

    #[Test]
    public function an_owner_can_still_read_their_own_non_marketplace_listing(): void
    {
        // Marketplace *browse* is active-only, but the marketplace detail route
        // has always let an owner read their own listing so a seller can check on
        // a draft. That overlap is deliberate [D-02 rules 1 and 5] and is what the
        // seller's detail screen reuses, so it is asserted here rather than left
        // to be discovered.
        $draft = $this->createListing($this->seller, ['status' => ListingStatus::Draft]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->getJson('/api/listings/'.$draft->id)
            ->assertOk()
            ->assertJsonPath('data.status', ListingStatus::Draft->value);
    }

    #[Test]
    public function another_buyer_cannot_read_a_draft(): void
    {
        $draft = $this->createListing($this->seller, ['status' => ListingStatus::Draft]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->buyer))
            ->getJson('/api/listings/'.$draft->id)
            ->assertNotFound();
    }

    #[Test]
    public function an_active_listing_appears_in_the_marketplace(): void
    {
        $this->createListing($this->seller, ['status' => ListingStatus::Active]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->buyer))
            ->getJson('/api/listings')
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 1);
    }

    #[Test]
    public function the_seller_api_exposes_no_publish_or_deactivate_route(): void
    {
        // The strongest form of the guarantee. "A seller cannot set `active`" is
        // asserted behaviourally above, but it is also worth asserting that there
        // is no endpoint at all for a seller to activate or withdraw a listing:
        // such a rule cannot be forgotten inside a controller, because there is
        // no controller to forget it in.
        $sellerRoutes = collect(app('router')->getRoutes())
            ->filter(fn ($route): bool => str_starts_with($route->uri(), 'api/seller/listings'))
            ->flatMap(fn ($route): array => array_map(
                // `HEAD` is registered implicitly for every `GET` and says
                // nothing on its own.
                fn (string $method): string => $method.' '.$route->uri(),
                array_values(array_diff($route->methods(), ['HEAD'])),
            ))
            ->unique()
            ->values()
            ->all();

        $this->assertEqualsCanonicalizing(
            [
                'GET api/seller/listings',
                'POST api/seller/listings',
                'POST api/seller/listings/{listing}/submit',
                'PATCH api/seller/listings/{listing}',
                'DELETE api/seller/listings/{listing}',
                // Listing photos (functional documentation §4.5, D-10): file
                // upload and removal, scoped to the caller's own listings like
                // everything above. They change no listing status.
                'POST api/seller/listings/{listing}/photos',
                'DELETE api/seller/listings/{listing}/photos',
            ],
            $sellerRoutes,
        );
    }
}
