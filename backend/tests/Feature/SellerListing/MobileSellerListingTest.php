<?php

namespace Tests\Feature\SellerListing;

use App\Enums\ActivityAction;
use App\Enums\ListingStatus;
use App\Enums\TransactionStatus;
use App\Enums\UserRole;
use App\Models\Activity;
use App\Models\Listing;
use App\Models\Setting;
use App\Models\Transaction;
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
 * it, edit a draft or an active listing, deactivate/reactivate eligible listings,
 * mark an active listing as sold, and delete only listings without transaction
 * history. Every other transition or another seller's row is refused, and each refusal is asserted
 * rather than assumed: this is the surface where "the client just won't offer
 * that button" is not a security property.
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
            'age_information' => 'known',
            'gender' => 'male',
            'weight_value' => 500,
            'weight_unit' => 'kg',
            'weight_information' => 'measured',
            'quantity' => 1,
            'asking_price' => 50000.00,
            'location' => 'Purok 3, Barangay Poblacion, Trinidad, Bohol',
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
        $payload = array_merge([
            'livestock_type' => 'cattle',
            'location' => 'Purok 3, Barangay Poblacion, Trinidad, Bohol',
            'asking_price' => 50000,
            'quantity' => 3,
            'age_value' => 2,
            'age_unit' => 'year',
            'age_information' => 'known',
            'weight_value' => 500,
            'weight_unit' => 'kg',
            'weight_information' => 'measured',
        ], $body);

        if (array_key_exists('total_quantity', $body) && ! array_key_exists('quantity', $body)) {
            unset($payload['quantity']);
        }

        return $this->withHeader(
            'Authorization',
            'Bearer '.($token ?? $this->mobileToken($this->seller)),
        )->postJson('/api/seller/listings', $payload);
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
            'markSold' => ['POST', '/api/seller/listings/{listing}/mark-sold'],
            'deactivate' => ['POST', '/api/seller/listings/{listing}/deactivate'],
            'reactivate' => ['POST', '/api/seller/listings/{listing}/reactivate'],
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
    public function a_new_client_can_create_with_total_quantity_and_legacy_quantity_remains_available(): void
    {
        $data = $this->store(['total_quantity' => 4])
            ->assertCreated()
            ->assertJsonPath('data.quantity', 4)
            ->assertJsonPath('data.total_quantity', 4)
            ->assertJsonPath('data.available_quantity', 4)
            ->assertJsonPath('data.reserved_quantity', 0)
            ->assertJsonPath('data.sold_quantity', 0)
            ->json('data');

        $this->assertSame(4, (int) Listing::query()->findOrFail($data['id'])->total_quantity);
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
    public function the_required_fields_are_required(): void
    {
        // The asking price and location are publication requirements, not draft
        // requirements, so they are deliberately absent from this list. The
        // submission test below asserts that they are still required to publish.
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings', [])
            ->assertStatus(422)
            ->assertJsonValidationErrors([
                'livestock_type',
                'quantity',
                'total_quantity',
                'age_value',
                'age_unit',
                'age_information',
                'weight_value',
                'weight_unit',
                'weight_information',
            ]);
    }

    #[Test]
    public function a_draft_can_be_created_without_an_asking_price_or_location(): void
    {
        $response = $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings', [
                'livestock_type' => 'cattle',
                'quantity' => 3,
                'age_value' => 2,
                'age_unit' => 'year',
                'age_information' => 'known',
                'weight_value' => 500,
                'weight_unit' => 'kg',
                'weight_information' => 'measured',
            ]);

        $response->assertCreated()
            ->assertJsonPath('data.status', ListingStatus::Draft->value)
            ->assertJsonPath('data.asking_price', null)
            ->assertJsonPath('data.location', null);

        $this->assertDatabaseHas('listings', [
            'id' => $response->json('data.id'),
            'asking_price' => null,
            'location' => null,
            'status' => ListingStatus::Draft->value,
        ]);
    }

    #[Test]
    public function pounds_are_stored_and_returned_without_conversion(): void
    {
        $response = $this->store([
            'weight_value' => 1102.31,
            'weight_unit' => 'lb',
        ]);

        $response->assertCreated()
            ->assertJsonPath('data.weight_value', '1102.31')
            ->assertJsonPath('data.weight_unit', 'lb');

        $this->assertDatabaseHas('listings', [
            'id' => $response->json('data.id'),
            'weight_value' => 1102.31,
            'weight_unit' => 'lb',
        ]);
    }

    /**
     * @return array<string, array{string}>
     */
    public static function unsupportedLivestockTypes(): array
    {
        return [
            'capitalized' => ['Cattle'],
            'outside scope' => ['poultry'],
            'free text' => ['Cow'],
        ];
    }

    #[Test]
    #[DataProvider('unsupportedLivestockTypes')]
    public function a_seller_cannot_create_a_listing_with_an_unsupported_type(string $type): void
    {
        $this->store(['livestock_type' => $type])
            ->assertStatus(422)
            ->assertJsonValidationErrors('livestock_type');

        $this->assertDatabaseCount('listings', 0);
    }

    /**
     * @return array<string, array{string}>
     */
    public static function approvedLivestockTypes(): array
    {
        return [
            'cattle' => ['cattle'],
            'carabao' => ['carabao'],
            'goat' => ['goat'],
            'swine' => ['swine'],
            'chicken' => ['chicken'],
        ];
    }

    #[Test]
    #[DataProvider('approvedLivestockTypes')]
    public function a_seller_can_create_each_approved_type(string $type): void
    {
        $this->store(['livestock_type' => $type])
            ->assertCreated()
            ->assertJsonPath('data.livestock_type', $type);
    }

    #[Test]
    public function a_new_listing_location_must_use_a_supported_trinidad_barangay(): void
    {
        foreach ([
            'Purok 3, Barangay Unknown, Trinidad, Bohol',
            'Purok 3, Barangay Poblacion, Tagbilaran, Bohol',
            'Purok 3, Barangay Poblacion, Trinidad, Cebu',
        ] as $location) {
            $this->store(['location' => $location])
                ->assertUnprocessable()
                ->assertJsonValidationErrors('location');
        }

        $this->assertDatabaseCount('listings', 0);
    }

    #[Test]
    public function a_catalog_breed_must_match_its_livestock_type(): void
    {
        $this->store([
            'livestock_type' => 'chicken',
            'breed' => 'Broiler',
        ])->assertCreated()
            ->assertJsonPath('data.livestock_type', 'chicken')
            ->assertJsonPath('data.breed', 'Broiler');

        $this->store([
            'livestock_type' => 'chicken',
            'breed' => 'Brahman',
        ])->assertStatus(422)
            ->assertJsonValidationErrors('breed');
    }

    #[Test]
    public function a_half_supplied_value_and_unit_pair_is_rejected(): void
    {
        $this->store(['age_unit' => null])
            ->assertStatus(422)
            ->assertJsonValidationErrors('age_unit');

        $this->store(['weight_value' => null])
            ->assertStatus(422)
            ->assertJsonValidationErrors('weight_value');
    }

    #[Test]
    public function age_and_weight_information_are_required_on_create(): void
    {
        $this->store(['age_value' => null])
            ->assertStatus(422)
            ->assertJsonValidationErrors('age_value');

        $this->store(['age_unit' => null])
            ->assertStatus(422)
            ->assertJsonValidationErrors('age_unit');

        $this->store(['age_information' => null])
            ->assertStatus(422)
            ->assertJsonValidationErrors('age_information');

        $this->store(['weight_value' => null])
            ->assertStatus(422)
            ->assertJsonValidationErrors('weight_value');

        $this->store(['weight_unit' => null])
            ->assertStatus(422)
            ->assertJsonValidationErrors('weight_unit');

        $this->store(['weight_information' => null])
            ->assertStatus(422)
            ->assertJsonValidationErrors('weight_information');
    }

    #[Test]
    public function age_and_weight_information_are_persisted_and_returned(): void
    {
        $this->store([
            'age_information' => 'estimated',
            'weight_information' => 'estimated',
        ])->assertCreated()
            ->assertJsonPath('data.age_information', 'estimated')
            ->assertJsonPath('data.weight_information', 'estimated');

        $this->assertDatabaseHas('listings', [
            'age_information' => 'estimated',
            'weight_information' => 'estimated',
        ]);
    }

    #[Test]
    public function an_update_can_change_both_information_types(): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Draft]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, [
                'age_value' => 2,
                'age_unit' => 'year',
                'age_information' => 'estimated',
                'weight_value' => 500,
                'weight_unit' => 'kg',
                'weight_information' => 'estimated',
            ])
            ->assertOk()
            ->assertJsonPath('data.age_information', 'estimated')
            ->assertJsonPath('data.weight_information', 'estimated');

        $this->assertDatabaseHas('listings', [
            'id' => $listing->id,
            'age_information' => 'estimated',
            'weight_information' => 'estimated',
        ]);
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
                'age_information' => 'known',
            ])
            ->assertOk();

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, [
                'age_value' => $aboveMaximum,
                'age_unit' => $unit,
                'age_information' => 'known',
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
                'breed' => 'Brahman',
            ])
            ->assertOk()
            ->assertJsonPath('data.asking_price', '62500.00')
            ->assertJsonPath('data.breed', 'Brahman')
            // Untouched fields stay untouched: this is a PATCH, not a replace.
            ->assertJsonPath(
                'data.location',
                'Purok 3, Barangay Poblacion, Trinidad, Bohol',
            );
    }

    #[Test]
    public function an_unchanged_legacy_location_can_be_saved_but_not_replaced_with_an_invalid_one(): void
    {
        $listing = $this->createListing($this->seller, [
            'status' => ListingStatus::Draft,
            'location' => 'Trinidad, Bohol',
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, [
                'quantity' => 2,
                'location' => 'Trinidad, Bohol',
            ])
            ->assertOk()
            ->assertJsonPath('data.location', 'Trinidad, Bohol');

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, [
                'location' => 'Barangay Poblacion, Tagbilaran, Bohol',
            ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('location');
    }

    #[Test]
    public function changing_type_without_a_breed_clears_the_previous_breed(): void
    {
        $listing = $this->createListing($this->seller, [
            'status' => ListingStatus::Draft,
            'breed' => 'Brahman',
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, [
                'livestock_type' => 'chicken',
            ])
            ->assertOk()
            ->assertJsonPath('data.livestock_type', 'chicken')
            ->assertJsonPath('data.breed', '');
    }

    #[Test]
    public function an_unedited_legacy_free_text_breed_is_allowed_once_its_type_is_re_sent(): void
    {
        // The mobile edit form always sends the listing's type together with
        // its breed, so this is the exact shape of an unrelated save of a
        // listing whose breed predates the catalog. It is exercised while the
        // type check is live, not by sending `breed` alone.
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Draft]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, [
                'livestock_type' => 'cattle',
                'breed' => 'Angus',
            ])
            ->assertOk()
            ->assertJsonPath('data.breed', 'Angus')
            ->assertJsonPath('data.livestock_type', 'cattle');
    }

    #[Test]
    public function a_breed_that_was_not_stored_must_come_from_the_catalog(): void
    {
        // Same request shape, but a value that was never stored: the
        // unchanged-legacy exemption must not become a free pass.
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Draft]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, [
                'livestock_type' => 'cattle',
                'breed' => 'Hereford',
            ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('breed');
    }

    #[Test]
    public function an_edit_rejects_an_unsupported_livestock_type(): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Draft]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, [
                'livestock_type' => 'poultry',
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('livestock_type');

        $this->assertDatabaseHas('listings', [
            'id' => $listing->id,
            'livestock_type' => 'cattle',
        ]);
    }

    #[Test]
    public function an_edit_to_a_legacy_listing_requires_a_supported_replacement(): void
    {
        $listing = $this->createListing($this->seller, [
            'status' => ListingStatus::Draft,
            'livestock_type' => 'poultry',
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, ['breed' => 'Anglo-Nubian'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('livestock_type');

        $this->assertDatabaseHas('listings', [
            'id' => $listing->id,
            'livestock_type' => 'poultry',
            'breed' => 'Angus',
        ]);
    }

    #[Test]
    public function an_edit_can_replace_a_legacy_type_with_an_approved_one(): void
    {
        $listing = $this->createListing($this->seller, [
            'status' => ListingStatus::Draft,
            'livestock_type' => 'poultry',
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, [
                'livestock_type' => 'goat',
                'breed' => 'Boer',
            ])
            ->assertOk()
            ->assertJsonPath('data.livestock_type', 'goat')
            ->assertJsonPath('data.breed', 'Boer');
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
    public function changing_total_quantity_preserves_accounted_sales_and_rejects_totals_below_commitments(): void
    {
        $listing = $this->createListing($this->seller, [
            'status' => ListingStatus::Active,
            'quantity' => 2,
            'total_quantity' => 5,
        ]);
        Transaction::query()->create([
            'buyer_id' => User::factory()->create()->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'quantity' => 3,
            'total_amount' => 150000,
            'inventory_reserved' => true,
            'inventory_accounted' => true,
            'status' => TransactionStatus::Completed,
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, ['total_quantity' => 2])
            ->assertStatus(409);

        $this->assertSame(5, (int) $listing->refresh()->total_quantity);
        $this->assertSame(2, (int) $listing->quantity);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, ['total_quantity' => 4])
            ->assertOk()
            ->assertJsonPath('data.total_quantity', 4)
            ->assertJsonPath('data.sold_quantity', 3)
            ->assertJsonPath('data.available_quantity', 1);

        $this->assertSame(1, (int) $listing->refresh()->quantity);
    }

    #[Test]
    public function an_active_listing_quantity_cannot_be_changed_while_stock_is_reserved(): void
    {
        $listing = $this->createListing($this->seller, [
            'status' => ListingStatus::Active,
            'quantity' => 4,
        ]);

        Transaction::create([
            'buyer_id' => $this->buyer->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'quantity' => 1,
            'total_amount' => 50000.00,
            'inventory_reserved' => true,
            'status' => TransactionStatus::Pending,
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, ['quantity' => 5])
            ->assertStatus(409);

        $this->assertSame(4, $listing->refresh()->quantity);

        // Unrelated edits are still allowed.
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, ['breed' => 'Brahman'])
            ->assertOk()
            ->assertJsonPath('data.breed', 'Brahman');
    }

    #[Test]
    public function a_partial_update_does_not_demand_the_required_fields(): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Draft]);

        // A seller correcting one field must not receive errors about the three
        // they never touched. This is the assertion that catches a `required`
        // rule left in place on the PATCH path.
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, ['breed' => 'Brahman'])
            ->assertOk()
            ->assertJsonPath('data.breed', 'Brahman')
            ->assertJsonPath('data.livestock_type', 'cattle')
            ->assertJsonPath('data.asking_price', '50000.00');
    }

    #[Test]
    public function a_legacy_incomplete_listing_can_be_edited_but_not_submitted_until_complete(): void
    {
        $listing = $this->createListing($this->seller, [
            'status' => ListingStatus::Draft,
            'age_value' => null,
            'age_unit' => null,
            'age_information' => null,
        ]);

        // A legacy draft may still be edited without backfilling its missing
        // measurement; the unrelated field is updated and the missing age stays
        // missing.
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, ['quantity' => 4])
            ->assertOk()
            ->assertJsonPath('data.quantity', 4)
            ->assertJsonPath('data.age_value', null)
            ->assertJsonPath('data.age_unit', null);

        // Starting to change a measurement requires the complete set, so a half
        // pair cannot be written.
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, ['age_value' => 30])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['age_unit', 'age_information']);

        // Submission is where completeness is enforced.
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings/'.$listing->id.'/submit')
            ->assertStatus(422)
            ->assertJsonValidationErrors(['age_value', 'age_unit', 'age_information']);
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
    public function a_draft_without_an_asking_price_or_location_can_be_updated(): void
    {
        $listing = $this->createListing($this->seller, [
            'status' => ListingStatus::Draft,
            'asking_price' => null,
            'location' => null,
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, ['quantity' => 4])
            ->assertOk()
            ->assertJsonPath('data.quantity', 4)
            ->assertJsonPath('data.asking_price', null)
            ->assertJsonPath('data.location', null);
    }

    #[Test]
    public function a_draft_without_an_asking_price_or_location_cannot_be_submitted(): void
    {
        $listing = $this->createListing($this->seller, [
            'status' => ListingStatus::Draft,
            'asking_price' => null,
            'location' => null,
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings/'.$listing->id.'/submit')
            ->assertStatus(422)
            ->assertJsonValidationErrors(['asking_price', 'location']);

        $this->assertDatabaseHas('listings', [
            'id' => $listing->id,
            'status' => ListingStatus::Draft->value,
            'asking_price' => null,
            'location' => null,
        ]);
    }

    #[Test]
    public function a_draft_can_be_submitted_after_adding_an_asking_price_and_location(): void
    {
        $listing = $this->createListing($this->seller, [
            'status' => ListingStatus::Draft,
            'asking_price' => null,
            'location' => null,
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson('/api/seller/listings/'.$listing->id, [
                'asking_price' => 50000,
                'location' => 'Purok 3, Barangay Poblacion, Trinidad, Bohol',
            ])
            ->assertOk()
            ->assertJsonPath('data.asking_price', '50000.00')
            ->assertJsonPath('data.location', 'Purok 3, Barangay Poblacion, Trinidad, Bohol');

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings/'.$listing->id.'/submit')
            ->assertOk()
            ->assertJsonPath('data.status', ListingStatus::Pending->value);
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
    public function a_legacy_unsupported_type_cannot_be_submitted(): void
    {
        $listing = $this->createListing($this->seller, [
            'status' => ListingStatus::Draft,
            'livestock_type' => 'poultry',
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings/'.$listing->id.'/submit')
            ->assertStatus(422)
            ->assertJsonValidationErrors('livestock_type');

        $this->assertDatabaseHas('listings', [
            'id' => $listing->id,
            'status' => ListingStatus::Draft->value,
        ]);
    }

    #[Test]
    public function a_legacy_unmapped_location_must_be_replaced_before_submission(): void
    {
        $listing = $this->createListing($this->seller, [
            'status' => ListingStatus::Draft,
            'location' => 'Trinidad, Bohol',
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings/'.$listing->id.'/submit')
            ->assertUnprocessable()
            ->assertJsonValidationErrors('location');

        $this->assertDatabaseHas('listings', [
            'id' => $listing->id,
            'status' => ListingStatus::Draft->value,
            'location' => 'Trinidad, Bohol',
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

    // ---------------------------------------------------------------- mark sold

    #[Test]
    public function an_active_listing_can_be_marked_as_sold(): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Active]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings/'.$listing->id.'/mark-sold')
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('message', 'Listing marked as sold.')
            ->assertJsonPath('data.status', ListingStatus::Sold->value)
            ->assertJsonPath('data.quantity', 0)
            ->assertJsonPath('data.externally_sold_quantity', 1)
            ->assertJsonPath('data.id', $listing->id);

        $this->assertDatabaseHas('listings', [
            'id' => $listing->id,
            'status' => ListingStatus::Sold->value,
            'quantity' => 0,
            'externally_sold_quantity' => 1,
        ]);

        $this->assertDatabaseHas('activities', [
            'user_id' => $this->seller->id,
            'action' => ActivityAction::ListingMarkedSold->value,
        ]);
    }

    #[Test]
    public function a_seller_can_deactivate_without_changing_reserved_inventory_or_transactions(): void
    {
        $listing = $this->createListing($this->seller, [
            'status' => ListingStatus::Active,
            'quantity' => 5,
        ]);
        $listing->quantity = 3;
        $listing->save();
        $transaction = Transaction::query()->create([
            'buyer_id' => $this->buyer->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'quantity' => 2,
            'total_amount' => 100000,
            'inventory_reserved' => true,
            'inventory_accounted' => true,
            'status' => TransactionStatus::Pending,
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings/'.$listing->id.'/deactivate')
            ->assertOk()
            ->assertJsonPath('data.status', ListingStatus::Inactive->value)
            ->assertJsonPath('data.quantity', 3)
            ->assertJsonPath('data.reserved_quantity', 2);

        $this->assertSame(ListingStatus::Inactive, $listing->refresh()->status);
        $this->assertSame(3, (int) $listing->quantity);
        $this->assertSame(2, (int) $transaction->fresh()->quantity);
        $this->assertTrue((bool) $transaction->fresh()->inventory_reserved);
        $this->assertDatabaseHas('activities', [
            'user_id' => $this->seller->id,
            'action' => ActivityAction::ListingSellerDeactivated->value,
        ]);
    }

    #[Test]
    public function deactivation_and_reactivation_reject_client_supplied_status(): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Active]);
        $token = $this->mobileToken($this->seller);

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson('/api/seller/listings/'.$listing->id.'/deactivate', ['status' => 'inactive'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('status');
        $this->assertSame(ListingStatus::Active, $listing->refresh()->status);

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson('/api/seller/listings/'.$listing->id.'/deactivate')
            ->assertOk();
        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson('/api/seller/listings/'.$listing->id.'/reactivate', ['status' => 'active'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('status');
        $this->assertSame(ListingStatus::Inactive, $listing->refresh()->status);
    }

    #[Test]
    public function a_seller_can_reactivate_only_their_own_voluntarily_deactivated_listing(): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Active]);
        $token = $this->mobileToken($this->seller);

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson('/api/seller/listings/'.$listing->id.'/deactivate')
            ->assertOk()
            ->assertJsonPath('data.seller_can_reactivate', true);

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson('/api/seller/listings/'.$listing->id.'/reactivate')
            ->assertOk()
            ->assertJsonPath('data.status', ListingStatus::Active->value)
            ->assertJsonPath('data.quantity', 1);

        $this->assertSame(ListingStatus::Active, $listing->refresh()->status);
        $this->assertDatabaseHas('activities', [
            'user_id' => $this->seller->id,
            'action' => ActivityAction::ListingSellerReactivated->value,
        ]);
    }

    #[Test]
    public function seller_actions_are_owner_scoped_and_deactivation_requires_active_status(): void
    {
        $foreignActive = $this->createListing($this->otherSeller, ['status' => ListingStatus::Active]);
        $foreignInactive = $this->createListing($this->otherSeller, ['status' => ListingStatus::Inactive]);
        $token = $this->mobileToken($this->seller);

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson('/api/seller/listings/'.$foreignActive->id.'/deactivate')
            ->assertNotFound();
        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson('/api/seller/listings/'.$foreignInactive->id.'/reactivate')
            ->assertNotFound();

        foreach ([ListingStatus::Draft, ListingStatus::Pending, ListingStatus::Sold, ListingStatus::Inactive] as $status) {
            $listing = $this->createListing($this->seller, ['status' => $status]);
            $this->withHeader('Authorization', 'Bearer '.$token)
                ->postJson('/api/seller/listings/'.$listing->id.'/deactivate')
                ->assertStatus(409);
            $this->assertSame($status, $listing->refresh()->status);
        }
    }

    #[Test]
    public function seller_reactivation_refuses_admin_deactivated_and_sold_listings(): void
    {
        $admin = User::factory()->admin()->create();
        $adminDeactivated = $this->createListing($this->seller, ['status' => ListingStatus::Inactive]);
        Activity::query()->create([
            'user_id' => $admin->id,
            'action' => ActivityAction::ListingDeactivated->value,
            'metadata' => [
                'target_type' => 'listing',
                'target_id' => $adminDeactivated->id,
            ],
        ]);
        $sold = $this->createListing($this->seller, ['status' => ListingStatus::Sold]);

        foreach ([$adminDeactivated, $sold] as $listing) {
            $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
                ->postJson('/api/seller/listings/'.$listing->id.'/reactivate')
                ->assertStatus(409);
        }

        $this->assertSame(ListingStatus::Inactive, $adminDeactivated->refresh()->status);
        $this->assertSame(ListingStatus::Sold, $sold->refresh()->status);
    }

    #[Test]
    public function seller_reactivation_refuses_unavailable_or_unreconciled_inventory(): void
    {
        $empty = $this->createListing($this->seller, [
            'status' => ListingStatus::Active,
            'quantity' => 0,
            'total_quantity' => 1,
            'externally_sold_quantity' => 1,
        ]);
        $unreconciled = $this->createListing($this->seller, [
            'status' => ListingStatus::Active,
            'inventory_reconciliation_required' => true,
        ]);
        $token = $this->mobileToken($this->seller);

        foreach ([$empty, $unreconciled] as $listing) {
            $this->withHeader('Authorization', 'Bearer '.$token)
                ->postJson('/api/seller/listings/'.$listing->id.'/deactivate')
                ->assertOk();
            $this->withHeader('Authorization', 'Bearer '.$token)
                ->postJson('/api/seller/listings/'.$listing->id.'/reactivate')
                ->assertStatus(409);
            $this->assertSame(ListingStatus::Inactive, $listing->refresh()->status);
        }
    }

    #[Test]
    public function a_seller_cannot_manually_sell_stock_while_a_transaction_reserves_it(): void
    {
        $listing = $this->createListing($this->seller, [
            'status' => ListingStatus::Active,
            'quantity' => 5,
        ]);
        $listing->quantity = 3;
        $listing->save();
        Transaction::query()->create([
            'buyer_id' => User::factory()->create()->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'quantity' => 2,
            'total_amount' => 100000,
            'inventory_reserved' => true,
            'inventory_accounted' => true,
            'status' => TransactionStatus::Pending,
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings/'.$listing->id.'/mark-sold')
            ->assertStatus(409);

        $this->assertSame(ListingStatus::Active, $listing->refresh()->status);
        $this->assertSame(3, (int) $listing->quantity);
        $this->assertSame(0, (int) $listing->externally_sold_quantity);
    }

    #[Test]
    public function a_mark_sold_cannot_carry_a_status_or_seller_id(): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Active]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings/'.$listing->id.'/mark-sold', ['status' => 'active'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('status');

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings/'.$listing->id.'/mark-sold', [
                'seller_id' => $this->otherSeller->id,
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('seller_id');

        // Rejected before the controller: the listing is still active.
        $this->assertDatabaseHas('listings', [
            'id' => $listing->id,
            'status' => ListingStatus::Active->value,
        ]);
    }

    /**
     * @return array<string, array{ListingStatus}>
     */
    public static function nonSellableStatuses(): array
    {
        return [
            'draft' => [ListingStatus::Draft],
            'pending' => [ListingStatus::Pending],
            'sold' => [ListingStatus::Sold],
            'inactive' => [ListingStatus::Inactive],
        ];
    }

    #[Test]
    #[DataProvider('nonSellableStatuses')]
    public function a_non_active_listing_cannot_be_marked_as_sold(ListingStatus $status): void
    {
        $listing = $this->createListing($this->seller, ['status' => $status]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings/'.$listing->id.'/mark-sold')
            ->assertStatus(409);

        $this->assertDatabaseHas('listings', [
            'id' => $listing->id,
            'status' => $status->value,
        ]);
    }

    #[Test]
    public function a_seller_cannot_mark_another_sellers_listing_as_sold(): void
    {
        $listing = $this->createListing($this->otherSeller, ['status' => ListingStatus::Active]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->postJson('/api/seller/listings/'.$listing->id.'/mark-sold')
            ->assertNotFound();

        $this->assertDatabaseHas('listings', [
            'id' => $listing->id,
            'status' => ListingStatus::Active->value,
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

    #[Test]
    public function seller_listing_projection_hides_delete_when_transaction_history_exists(): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Inactive]);
        Transaction::query()->create([
            'buyer_id' => $this->buyer->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'quantity' => 1,
            'total_amount' => 50000,
            'inventory_reserved' => false,
            'inventory_accounted' => false,
            'status' => TransactionStatus::Cancelled,
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->getJson('/api/seller/listings?status=inactive')
            ->assertOk()
            ->assertJsonPath('data.listings.0.seller_can_delete', false)
            ->assertJsonPath('data.listings.0.seller_can_reactivate', false);
    }

    #[Test]
    #[DataProvider('transactionHistoryStatuses')]
    public function a_listing_with_any_transaction_history_cannot_be_deleted(TransactionStatus $status): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Inactive]);
        $transaction = Transaction::query()->create([
            'buyer_id' => $this->buyer->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'quantity' => 1,
            'total_amount' => 50000,
            'inventory_reserved' => $status === TransactionStatus::Pending,
            'inventory_accounted' => $status === TransactionStatus::Pending,
            'status' => $status,
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->deleteJson('/api/seller/listings/'.$listing->id)
            ->assertStatus(409);

        $this->assertDatabaseHas('listings', ['id' => $listing->id]);
        $this->assertDatabaseHas('transactions', ['id' => $transaction->id, 'listing_id' => $listing->id]);
    }

    /** @return array<string, array{TransactionStatus}> */
    public static function transactionHistoryStatuses(): array
    {
        return [
            'pending' => [TransactionStatus::Pending],
            'completed' => [TransactionStatus::Completed],
            'cancelled' => [TransactionStatus::Cancelled],
        ];
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
    public function seller_deactivation_hides_the_listing_and_reactivation_restores_visibility(): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Active]);
        $sellerToken = $this->mobileToken($this->seller);
        $buyerToken = $this->mobileToken($this->buyer);

        $this->withHeader('Authorization', 'Bearer '.$sellerToken)
            ->postJson('/api/seller/listings/'.$listing->id.'/deactivate')
            ->assertOk();
        $this->withHeader('Authorization', 'Bearer '.$buyerToken)
            ->getJson('/api/listings')
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 0);

        $this->withHeader('Authorization', 'Bearer '.$sellerToken)
            ->postJson('/api/seller/listings/'.$listing->id.'/reactivate')
            ->assertOk();
        $this->withHeader('Authorization', 'Bearer '.$buyerToken)
            ->getJson('/api/listings')
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 1);
    }

    #[Test]
    public function the_seller_api_exposes_no_publish_or_admin_moderation_route(): void
    {
        // There is no seller publication or administrator-moderation bypass.
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
                'POST api/seller/listings/{listing}/mark-sold',
                'POST api/seller/listings/{listing}/deactivate',
                'POST api/seller/listings/{listing}/reactivate',
                'PATCH api/seller/listings/{listing}',
                'DELETE api/seller/listings/{listing}',
                // Listing photos (functional documentation §4.5, D-10): file
                // upload and removal, scoped to the caller's own listings like
                // everything above. They change no listing status.
                'POST api/seller/listings/{listing}/photos',
                'DELETE api/seller/listings/{listing}/photos',
                // Optional decision support; accepts no body and does not
                // change asking_price or listing status.
                'POST api/seller/listings/{listing}/price-suggestion',
            ],
            $sellerRoutes,
        );
    }
}
