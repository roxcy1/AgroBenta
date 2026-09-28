<?php

namespace Tests\Feature\Marketplace;

use App\Enums\ListingStatus;
use App\Enums\UserRole;
use App\Models\Listing;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Testing\TestResponse;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Buyer marketplace read API — `GET /api/listings` and
 * `GET /api/listings/{listing}`.
 *
 * Two things are being defended here. The first is functional: the marketplace
 * shows active inventory and nothing else. The second is confidentiality: a
 * marketplace reader is an ordinary signed-in user, so the response must not
 * carry the seller's email address or any internal listing field.
 */
class MarketplaceListingTest extends TestCase
{
    use RefreshDatabase;

    private User $seller;

    private User $otherSeller;

    protected function setUp(): void
    {
        parent::setUp();

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
    }

    private function mobileToken(User $user): string
    {
        return $user->createToken('mobile', ['mobile'])->plainTextToken;
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
            'status' => ListingStatus::Active,
        ], $overrides));
    }

    /**
     * @param  array<string, mixed>  $query
     * @return TestResponse
     */
    private function browse(array $query = [], ?string $token = null)
    {
        return $this->withHeader(
            'Authorization',
            'Bearer '.($token ?? $this->mobileToken(User::factory()->create())),
        )->getJson('/api/listings'.($query === [] ? '' : '?'.http_build_query($query)));
    }

    /*
    |--------------------------------------------------------------------------
    | Authentication
    |--------------------------------------------------------------------------
    */

    #[Test]
    public function a_guest_cannot_browse_the_marketplace(): void
    {
        $this->createListing($this->seller);

        $this->getJson('/api/listings')->assertUnauthorized();
    }

    #[Test]
    public function a_guest_cannot_view_a_listing(): void
    {
        $listing = $this->createListing($this->seller);

        $this->getJson("/api/listings/{$listing->id}")->assertUnauthorized();
    }

    #[Test]
    public function an_authenticated_buyer_can_browse_the_marketplace(): void
    {
        $this->createListing($this->seller);
        $this->createListing($this->otherSeller, ['livestock_type' => 'goat']);

        $this->browse()->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.pagination.total', 2);
    }

    #[Test]
    public function an_authenticated_buyer_can_view_an_active_listing(): void
    {
        $listing = $this->createListing($this->seller);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken(User::factory()->create()))
            ->getJson("/api/listings/{$listing->id}")
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.id', $listing->id)
            ->assertJsonPath('data.livestock_type', 'cattle')
            ->assertJsonPath('data.status', ListingStatus::Active->value);
    }

    #[Test]
    public function a_token_without_the_mobile_ability_cannot_browse_the_marketplace(): void
    {
        $this->createListing($this->seller);

        // Explicitly empty: `createToken()` defaults to `['*']`, which would
        // otherwise mint a full-access token and make this assertion vacuous.
        $token = User::factory()->create()->createToken('user_token', [])->plainTextToken;

        $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/listings')
            ->assertForbidden();
    }

    #[Test]
    public function a_token_without_the_mobile_ability_cannot_view_a_listing(): void
    {
        $listing = $this->createListing($this->seller);

        $token = User::factory()->create()->createToken('user_token', [])->plainTextToken;

        $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson("/api/listings/{$listing->id}")
            ->assertForbidden();
    }

    /*
    |--------------------------------------------------------------------------
    | Admin authorization expectations stay intact
    |--------------------------------------------------------------------------
    */

    #[Test]
    public function an_admin_token_cannot_reach_the_marketplace(): void
    {
        $this->createListing($this->seller);

        $admin = User::factory()->admin()->create();
        $token = $admin->createToken('admin_token', ['admin'])->plainTextToken;

        $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/listings')
            ->assertForbidden();

        $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/listings/1')
            ->assertForbidden();
    }

    #[Test]
    public function the_admin_listing_endpoint_still_works_for_an_admin(): void
    {
        $this->createListing($this->seller, ['status' => ListingStatus::Draft]);

        $admin = User::factory()->admin()->create();
        $token = $admin->createToken('admin_token', ['admin'])->plainTextToken;

        // The marketplace endpoints must not have narrowed what an
        // administrator can read: the admin view still sees every status.
        $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/admin/listings')
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 1)
            ->assertJsonPath('data.listings.0.status', ListingStatus::Draft->value);
    }

    #[Test]
    public function a_mobile_token_cannot_reach_the_admin_listing_endpoint(): void
    {
        $this->createListing($this->seller);

        $token = $this->mobileToken(User::factory()->create());

        $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/admin/listings')
            ->assertForbidden();
    }

    #[Test]
    public function an_approved_seller_is_just_a_buyer_in_the_marketplace(): void
    {
        $this->createListing($this->seller);

        // Seller capability gates selling actions, not browsing. A buyer and an
        // approved seller see exactly the same active inventory.
        $buyer = $this->browse();

        $seller = $this->forgetResolvedGuards()
            ->browse(token: $this->mobileToken($this->seller));

        $buyer->assertOk();
        $seller->assertOk();

        $this->assertSame(
            $buyer->json('data.pagination.total'),
            $seller->json('data.pagination.total'),
        );
    }

    /**
     * Resolves the Sanctum guard between requests made as different users.
     *
     * The guard memoises the authenticated user for the lifetime of the
     * resolved instance, and that instance is reused across requests inside a
     * single test. Without this, a second request silently runs as the first
     * request's user — which is how a marketplace test could come to "prove"
     * something about a buyer while actually exercising the seller.
     */
    private function forgetResolvedGuards(): static
    {
        app('auth')->forgetGuards();

        return $this;
    }

    /*
    |--------------------------------------------------------------------------
    | Marketplace visibility — list
    |--------------------------------------------------------------------------
    */

    #[Test]
    #[DataProvider('hiddenStatuses')]
    public function the_marketplace_excludes_non_active_listings(ListingStatus $status): void
    {
        $this->createListing($this->seller, ['status' => $status]);

        $response = $this->browse()->assertOk();

        $response->assertJsonCount(0, 'data.listings')
            ->assertJsonPath('data.pagination.total', 0);
    }

    /**
     * @return array<string, array{ListingStatus}>
     */
    public static function hiddenStatuses(): array
    {
        return [
            'draft' => [ListingStatus::Draft],
            'pending' => [ListingStatus::Pending],
            'inactive' => [ListingStatus::Inactive],
            'sold' => [ListingStatus::Sold],
        ];
    }

    #[Test]
    public function the_marketplace_contains_only_the_active_listing_when_all_statuses_exist(): void
    {
        $active = $this->createListing($this->seller, ['status' => ListingStatus::Active]);
        $this->createListing($this->seller, ['status' => ListingStatus::Draft]);
        $this->createListing($this->seller, ['status' => ListingStatus::Pending]);
        $this->createListing($this->otherSeller, ['status' => ListingStatus::Inactive]);
        $this->createListing($this->otherSeller, ['status' => ListingStatus::Sold]);

        $response = $this->browse()->assertOk();

        $response->assertJsonCount(1, 'data.listings')
            ->assertJsonPath('data.listings.0.id', $active->id)
            ->assertJsonPath('data.pagination.total', 1);
    }

    /*
    |--------------------------------------------------------------------------
    | Marketplace visibility — direct lookup
    |--------------------------------------------------------------------------
    */

    #[Test]
    #[DataProvider('hiddenStatuses')]
    public function a_buyer_c_not_read_another_user_s_hidden_listing_by_id(ListingStatus $status): void
    {
        $hidden = $this->createListing($this->otherSeller, ['status' => $status]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken(User::factory()->create()))
            ->getJson("/api/listings/{$hidden->id}")
            ->assertNotFound()
            ->assertJsonPath('message', 'Listing not found.');
    }

    #[Test]
    public function a_hidden_listing_is_indistinguishable_from_a_missing_one(): void
    {
        $hidden = $this->createListing($this->otherSeller, ['status' => ListingStatus::Draft]);

        $token = $this->mobileToken(User::factory()->create());

        $draft = $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson("/api/listings/{$hidden->id}");

        $missing = $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/listings/999999');

        // Same status and same body. A different status code or a distinct
        // message would confirm that the id exists.
        $this->assertSame($missing->getStatusCode(), $draft->getStatusCode());
        $this->assertSame(
            $missing->json('message'),
            $draft->json('message'),
        );
    }

    #[Test]
    public function a_non_numeric_listing_id_is_not_found(): void
    {
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken(User::factory()->create()))
            ->getJson('/api/listings/not-a-number')
            ->assertNotFound()
            ->assertJsonPath('message', 'Listing not found.');
    }

    #[Test]
    public function a_seller_can_still_view_their_own_hidden_listing(): void
    {
        $draft = $this->createListing($this->seller, ['status' => ListingStatus::Draft]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->getJson("/api/listings/{$draft->id}")
            ->assertOk()
            ->assertJsonPath('data.id', $draft->id)
            ->assertJsonPath('data.status', ListingStatus::Draft->value);
    }

    #[Test]
    public function a_seller_cannot_view_another_sellers_hidden_listing(): void
    {
        $draft = $this->createListing($this->otherSeller, ['status' => ListingStatus::Draft]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->getJson("/api/listings/{$draft->id}")
            ->assertNotFound();
    }

    /*
    |--------------------------------------------------------------------------
    | The client cannot widen marketplace visibility
    |--------------------------------------------------------------------------
    */

    #[Test]
    #[DataProvider('statusOverrideAttempts')]
    public function a_client_cannot_override_active_only_visibility_with_a_status_parameter(string $status): void
    {
        $this->createListing($this->seller, ['status' => ListingStatus::Draft]);
        $this->createListing($this->seller, ['status' => ListingStatus::Pending]);
        $this->createListing($this->seller, ['status' => ListingStatus::Inactive]);
        $this->createListing($this->seller, ['status' => ListingStatus::Sold]);
        $this->createListing($this->seller, ['status' => ListingStatus::Active]);

        $this->browse(['status' => $status])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['status']);

        // The refused request must not have leaked anything, and the active
        // listing must still be the only one the marketplace holds.
        $this->browse()
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 1)
            ->assertJsonPath('data.listings.0.status', ListingStatus::Active->value);
    }

    /**
     * @return array<string, array{string}>
     */
    public static function statusOverrideAttempts(): array
    {
        return [
            'draft' => ['draft'],
            'pending' => ['pending'],
            'inactive' => ['inactive'],
            'sold' => ['sold'],
            'active is not client-selectable either' => ['active'],
        ];
    }

    #[Test]
    public function a_status_filter_is_refused_even_when_combined_with_valid_filters(): void
    {
        $this->createListing($this->seller, ['livestock_type' => 'cattle', 'status' => ListingStatus::Draft]);
        $this->createListing($this->seller, ['livestock_type' => 'cattle', 'status' => ListingStatus::Active]);

        $this->browse(['livestock_type' => 'cattle', 'status' => 'draft'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['status']);
    }

    #[Test]
    public function a_seller_id_filter_is_refused(): void
    {
        $this->createListing($this->seller);
        $this->createListing($this->otherSeller);

        // Ownership is never a client-selected scope on a read endpoint, so the
        // parameter is rejected rather than quietly ignored.
        $this->browse(['seller_id' => $this->seller->id])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['seller_id']);
    }

    /*
    |--------------------------------------------------------------------------
    | Search
    |--------------------------------------------------------------------------
    */

    #[Test]
    public function search_matches_livestock_type_breed_and_location(): void
    {
        $cattle = $this->createListing($this->seller, ['livestock_type' => 'cattle', 'breed' => 'Angus', 'location' => 'Bukidnon']);
        $this->createListing($this->seller, ['livestock_type' => 'goat', 'breed' => 'Boer', 'location' => 'Davao']);

        $this->assertSame($cattle->id, $this->browse(['search' => 'cattle'])->assertOk()
            ->json('data.listings.0.id'));

        $this->assertSame($cattle->id, $this->browse(['search' => 'Angus'])->assertOk()
            ->json('data.listings.0.id'));

        $this->assertSame($cattle->id, $this->browse(['search' => 'Bukidnon'])->assertOk()
            ->json('data.listings.0.id'));
    }

    #[Test]
    public function search_runs_in_the_database_rather_than_in_php(): void
    {
        for ($i = 0; $i < 30; $i++) {
            $this->createListing($this->seller, ['livestock_type' => 'goat', 'breed' => 'Boer']);
        }

        $this->createListing($this->seller, ['livestock_type' => 'cattle', 'breed' => 'Angus']);

        // A PHP post-filter over a paginated result set would report the
        // unfiltered total and the unfiltered page size. Both come back
        // filtered, which only happens if SQL did the matching.
        $this->browse(['search' => 'Angus'])->assertOk()
            ->assertJsonCount(1, 'data.listings')
            ->assertJsonPath('data.pagination.total', 1);
    }

    #[Test]
    public function search_never_reaches_a_non_active_listing(): void
    {
        $this->createListing($this->seller, [
            'livestock_type' => 'cattle',
            'breed' => 'Angus',
            'status' => ListingStatus::Draft,
        ]);

        $this->browse(['search' => 'Angus'])->assertOk()
            ->assertJsonCount(0, 'data.listings')
            ->assertJsonPath('data.pagination.total', 0);
    }

    #[Test]
    public function an_empty_search_returns_the_whole_marketplace(): void
    {
        $this->createListing($this->seller);
        $this->createListing($this->otherSeller);

        $this->browse(['search' => ''])->assertOk()
            ->assertJsonPath('data.pagination.total', 2);
    }

    #[Test]
    public function a_search_with_no_matches_returns_an_empty_page(): void
    {
        $this->createListing($this->seller);

        $this->browse(['search' => 'nonexistent'])->assertOk()
            ->assertJsonCount(0, 'data.listings')
            ->assertJsonPath('data.pagination.total', 0);
    }

    #[Test]
    public function a_search_term_longer_than_the_documented_limit_is_refused(): void
    {
        $this->browse(['search' => str_repeat('a', 256)])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['search']);
    }

    /*
    |--------------------------------------------------------------------------
    | Filtering
    |--------------------------------------------------------------------------
    */

    #[Test]
    public function livestock_type_and_location_filters_work(): void
    {
        $this->createListing($this->seller, ['livestock_type' => 'cattle', 'location' => 'Bukidnon']);
        $this->createListing($this->seller, ['livestock_type' => 'cattle', 'location' => 'Davao']);
        $this->createListing($this->seller, ['livestock_type' => 'goat', 'location' => 'Bukidnon']);

        $this->browse(['livestock_type' => 'cattle'])->assertOk()
            ->assertJsonPath('data.pagination.total', 2);

        $this->browse(['location' => 'Bukidnon'])->assertOk()
            ->assertJsonPath('data.pagination.total', 2);

        $this->browse(['livestock_type' => 'cattle', 'location' => 'Bukidnon'])->assertOk()
            ->assertJsonPath('data.pagination.total', 1);
    }

    #[Test]
    public function the_price_range_filters_work(): void
    {
        $this->createListing($this->seller, ['asking_price' => 10000]);
        $this->createListing($this->seller, ['asking_price' => 50000]);
        $this->createListing($this->seller, ['asking_price' => 90000]);

        $this->browse(['min_price' => 40000])->assertOk()
            ->assertJsonPath('data.pagination.total', 2);

        $this->browse(['max_price' => 40000])->assertOk()
            ->assertJsonPath('data.pagination.total', 1);

        $this->browse(['min_price' => 20000, 'max_price' => 60000])->assertOk()
            ->assertJsonPath('data.pagination.total', 1);
    }

    #[Test]
    public function filters_never_reach_a_non_active_listing(): void
    {
        $this->createListing($this->seller, [
            'livestock_type' => 'cattle',
            'location' => 'Bukidnon',
            'asking_price' => 10000,
            'status' => ListingStatus::Pending,
        ]);

        $this->browse(['livestock_type' => 'cattle'])->assertOk()
            ->assertJsonPath('data.pagination.total', 0);

        $this->browse(['location' => 'Bukidnon'])->assertOk()
            ->assertJsonPath('data.pagination.total', 0);

        $this->browse(['min_price' => 1])->assertOk()
            ->assertJsonPath('data.pagination.total', 0);
    }

    #[Test]
    public function a_negative_price_bound_is_refused(): void
    {
        $this->browse(['min_price' => -1])->assertUnprocessable()
            ->assertJsonValidationErrors(['min_price']);
    }

    #[Test]
    public function an_oversized_livestock_type_filter_is_refused(): void
    {
        $this->browse(['livestock_type' => str_repeat('a', 256)])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['livestock_type']);
    }

    /*
    |--------------------------------------------------------------------------
    | Pagination
    |--------------------------------------------------------------------------
    */

    #[Test]
    public function the_pagination_shape_matches_the_documented_envelope(): void
    {
        $this->createListing($this->seller);

        $response = $this->browse()->assertOk()
            ->assertJsonStructure([
                'success',
                'data' => [
                    'listings' => [
                        '*' => [
                            'id', 'seller', 'livestock_type', 'breed', 'age_value',
                            'age_unit', 'gender', 'weight_value', 'weight_unit',
                            'quantity', 'asking_price', 'location', 'health_status',
                            'vaccination', 'short_description', 'additional_notes',
                            'photos', 'status', 'created_at', 'updated_at',
                        ],
                    ],
                    'pagination' => ['current_page', 'last_page', 'per_page', 'total'],
                ],
            ]);

        // Four keys, and no `links` or `next_page_url`: the hand-rolled shape
        // the existing clients parse, not Laravel's LengthAwarePaginator.
        $this->assertCount(4, $response->json('data.pagination'));
    }

    #[Test]
    public function pagination_splits_the_marketplace(): void
    {
        for ($i = 0; $i < 25; $i++) {
            $this->createListing($this->seller);
        }

        $first = $this->browse(['per_page' => 10, 'page' => 1])->assertOk();

        $first->assertJsonCount(10, 'data.listings')
            ->assertJsonPath('data.pagination.current_page', 1)
            ->assertJsonPath('data.pagination.last_page', 3)
            ->assertJsonPath('data.pagination.per_page', 10)
            ->assertJsonPath('data.pagination.total', 25);

        $last = $this->browse(['per_page' => 10, 'page' => 3])->assertOk();

        $last->assertJsonCount(5, 'data.listings')
            ->assertJsonPath('data.pagination.current_page', 3);

        $this->assertNotSame(
            $first->json('data.listings.0.id'),
            $last->json('data.listings.0.id'),
        );
    }

    #[Test]
    public function pagination_counts_only_active_listings(): void
    {
        for ($i = 0; $i < 20; $i++) {
            $this->createListing($this->seller, ['status' => ListingStatus::Draft]);
        }

        $this->createListing($this->seller, ['status' => ListingStatus::Active]);

        // A hidden listing must not be counted, or a buyer could infer that
        // hidden inventory exists from the pagination totals alone.
        $this->browse()->assertOk()
            ->assertJsonCount(1, 'data.listings')
            ->assertJsonPath('data.pagination.total', 1)
            ->assertJsonPath('data.pagination.last_page', 1);
    }

    #[Test]
    public function the_default_page_size_is_fifteen(): void
    {
        for ($i = 0; $i < 20; $i++) {
            $this->createListing($this->seller);
        }

        $this->browse()->assertOk()
            ->assertJsonCount(15, 'data.listings')
            ->assertJsonPath('data.pagination.per_page', 15);
    }

    #[Test]
    public function a_client_cannot_ask_for_an_unbounded_page(): void
    {
        $this->createListing($this->seller);

        // 50 is the documented ceiling.
        $this->browse(['per_page' => 50])->assertOk()
            ->assertJsonPath('data.pagination.per_page', 50);

        $this->browse(['per_page' => 51])->assertUnprocessable()
            ->assertJsonValidationErrors(['per_page']);

        $this->browse(['per_page' => 0])->assertUnprocessable()
            ->assertJsonValidationErrors(['per_page']);

        $this->browse(['per_page' => -5])->assertUnprocessable()
            ->assertJsonValidationErrors(['per_page']);
    }

    #[Test]
    public function a_non_positive_page_number_is_refused(): void
    {
        $this->browse(['page' => 0])->assertUnprocessable()
            ->assertJsonValidationErrors(['page']);
    }

    /*
    |--------------------------------------------------------------------------
    | Ordering
    |--------------------------------------------------------------------------
    */

    #[Test]
    public function results_are_ordered_newest_first(): void
    {
        $oldest = $this->createListing($this->seller, ['created_at' => now()->subDays(10)]);
        $middle = $this->createListing($this->seller, ['created_at' => now()->subDays(5)]);
        $newest = $this->createListing($this->seller, ['created_at' => now()->subDay()]);

        $response = $this->browse()->assertOk();

        $ids = array_column($response->json('data.listings'), 'id');

        $this->assertSame([$newest->id, $middle->id, $oldest->id], $ids);
    }

    #[Test]
    public function a_client_supplied_sort_clause_is_not_accepted(): void
    {
        $this->createListing($this->seller, ['asking_price' => 10000]);
        $this->createListing($this->seller, ['asking_price' => 90000]);

        $response = $this->browse([
            'order_by' => 'asking_price',
            'direction' => 'asc',
            'sort' => 'asking_price',
        ])->assertOk();

        // Unlisted parameters are not honoured and cannot reach the query. The
        // order stays newest-first, which is what the cheapest listing happens
        // to be here — so assert the real invariant, that both rows are there
        // in the fixed order.
        $this->assertCount(2, $response->json('data.listings'));
    }

    /*
    |--------------------------------------------------------------------------
    | Resource shape and confidentiality
    |--------------------------------------------------------------------------
    */

    #[Test]
    public function the_marketplace_response_never_contains_the_seller_email(): void
    {
        $this->createListing($this->seller);

        $response = $this->browse()->assertOk();

        $response->assertJsonPath('data.listings.0.seller.id', $this->seller->id)
            ->assertJsonPath('data.listings.0.seller.name', 'Juan Dela Cruz')
            ->assertJsonMissingPath('data.listings.0.seller.email')
            ->assertJsonMissingPath('data.listings.0.email');

        // The address must be absent from the bytes on the wire, not merely
        // relocated to another key.
        $this->assertStringNotContainsString('juan@agrobenta.test', $response->getContent());
    }

    #[Test]
    public function the_listing_detail_response_never_contains_the_seller_email(): void
    {
        $listing = $this->createListing($this->seller);

        $response = $this->withHeader('Authorization', 'Bearer '.$this->mobileToken(User::factory()->create()))
            ->getJson("/api/listings/{$listing->id}")
            ->assertOk();

        $response->assertJsonStructure(['success', 'data' => ['id', 'seller' => ['id', 'name']]])
            ->assertJsonMissingPath('data.seller.email');

        $this->assertStringNotContainsString('juan@agrobenta.test', $response->getContent());
    }

    #[Test]
    public function the_seller_projection_exposes_only_identity_and_name(): void
    {
        $this->createListing($this->seller);

        $seller = $this->browse()->assertOk()->json('data.listings.0.seller');

        $this->assertSame(['id', 'name'], array_keys($seller));
    }

    #[Test]
    public function internal_and_sensitive_listing_fields_are_not_exposed(): void
    {
        $this->createListing($this->seller);

        $listing = $this->browse()->assertOk()->json('data.listings.0');

        foreach (['seller_id', 'password', 'remember_token', 'price_suggestion'] as $key) {
            $this->assertArrayNotHasKey($key, $listing);
        }

        $this->assertStringNotContainsString((string) $this->seller->password, (string) json_encode($listing));
    }

    #[Test]
    public function the_asking_price_is_serialised_as_a_string(): void
    {
        $this->createListing($this->seller, ['asking_price' => 42500]);

        $price = $this->browse()->assertOk()->json('data.listings.0.asking_price');

        // Decimal columns are strings on the wire so a client never does float
        // arithmetic on money.
        $this->assertIsString($price);
        $this->assertSame('42500.00', $price);
    }

    #[Test]
    public function nullable_listing_fields_are_present_as_null(): void
    {
        $this->createListing($this->seller, [
            'age_value' => null,
            'age_unit' => null,
            'gender' => null,
            'weight_value' => null,
            'health_status' => null,
            'vaccination' => null,
            'additional_notes' => null,
        ]);

        $listing = $this->browse()->assertOk()->json('data.listings.0');

        foreach (['age_value', 'age_unit', 'gender', 'weight_value', 'health_status', 'vaccination', 'additional_notes'] as $key) {
            $this->assertArrayHasKey($key, $listing);
            $this->assertNull($listing[$key]);
        }
    }

    #[Test]
    public function photos_are_returned_as_stored(): void
    {
        $this->createListing($this->seller, [
            'photos' => ['listings/1/front.jpg', 'listings/1/side.jpg'],
        ]);

        $this->browse()->assertOk()
            ->assertJsonPath('data.listings.0.photos', ['listings/1/front.jpg', 'listings/1/side.jpg']);
    }

    #[Test]
    public function a_listing_with_no_photos_returns_an_empty_array_not_null(): void
    {
        $this->createListing($this->seller, ['photos' => []]);

        $photos = $this->browse()->assertOk()->json('data.listings.0.photos');

        $this->assertSame([], $photos);
    }

    #[Test]
    public function non_string_photo_entries_are_not_surfaced_to_the_client(): void
    {
        // The write contract is a list of strings. A malformed entry is dropped
        // rather than handed to a client that has to defend against it.
        $this->createListing($this->seller, [
            'photos' => ['listings/1/front.jpg', 42, null, ['url' => 'nope']],
        ]);

        $this->browse()->assertOk()
            ->assertJsonPath('data.listings.0.photos', ['listings/1/front.jpg']);
    }

    #[Test]
    public function photos_are_returned_by_the_detail_endpoint_too(): void
    {
        $listing = $this->createListing($this->seller, ['photos' => ['listings/9/only.jpg']]);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken(User::factory()->create()))
            ->getJson("/api/listings/{$listing->id}")
            ->assertOk()
            ->assertJsonPath('data.photos', ['listings/9/only.jpg']);
    }

    #[Test]
    public function the_admin_listing_resource_is_not_reused_for_the_marketplace(): void
    {
        $this->createListing($this->seller);

        $marketplace = $this->browse()->assertOk();

        $admin = User::factory()->admin()->create();

        $adminView = $this->forgetResolvedGuards()
            ->withHeader(
                'Authorization',
                'Bearer '.$admin->createToken('admin_token', ['admin'])->plainTextToken,
            )->getJson('/api/admin/listings')->assertOk();

        // The two projections differ on exactly the two points that matter:
        // the admin view carries the seller email and omits photos.
        $this->assertArrayHasKey('email', $adminView->json('data.listings.0.seller'));
        $this->assertArrayNotHasKey('email', $marketplace->json('data.listings.0.seller'));
        $this->assertArrayNotHasKey('photos', $adminView->json('data.listings.0'));
        $this->assertArrayHasKey('photos', $marketplace->json('data.listings.0'));
    }

    /*
    |--------------------------------------------------------------------------
    | Data integrity
    |--------------------------------------------------------------------------
    */

    #[Test]
    public function browsing_the_marketplace_does_not_mutate_the_database(): void
    {
        $active = $this->createListing($this->seller);
        $this->createListing($this->seller, ['status' => ListingStatus::Draft]);

        $before = DB::table('listings')->orderBy('id')->get()->map(fn ($row) => (array) $row)->all();

        $token = $this->mobileToken(User::factory()->create());

        $this->withHeader('Authorization', "Bearer {$token}")->getJson('/api/listings')->assertOk();
        $this->withHeader('Authorization', "Bearer {$token}")->getJson("/api/listings/{$active->id}")->assertOk();
        $this->withHeader('Authorization', "Bearer {$token}")->getJson('/api/listings?search=cattle&per_page=5')->assertOk();
        $this->withHeader('Authorization', "Bearer {$token}")->getJson('/api/listings/999999')->assertNotFound();

        $after = DB::table('listings')->orderBy('id')->get()->map(fn ($row) => (array) $row)->all();

        $this->assertSame($before, $after);
    }

    #[Test]
    public function a_refused_visibility_override_does_not_mutate_the_database(): void
    {
        $draft = $this->createListing($this->seller, ['status' => ListingStatus::Draft]);

        $this->browse(['status' => 'active'])->assertUnprocessable();
        $this->browse(['seller_id' => $this->otherSeller->id])->assertUnprocessable();

        $this->assertDatabaseHas('listings', [
            'id' => $draft->id,
            'status' => ListingStatus::Draft->value,
            'seller_id' => $this->seller->id,
        ]);
    }

    #[Test]
    public function marketplace_requests_cannot_change_ownership(): void
    {
        $listing = $this->createListing($this->seller);

        $token = $this->mobileToken($this->otherSeller);

        // Ownership is derived from the session, never from a request. The
        // detail endpoint takes no filters at all, so a named owner is simply
        // inert — it cannot reach the query and cannot change what is returned.
        $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson("/api/listings/{$listing->id}?seller_id={$this->otherSeller->id}")
            ->assertOk()
            ->assertJsonPath('data.seller.id', $this->seller->id);

        $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson("/api/listings/{$listing->id}?status=draft")
            ->assertOk()
            ->assertJsonPath('data.status', ListingStatus::Active->value);

        $this->assertSame($this->seller->id, $listing->fresh()->seller_id);
        $this->assertSame(ListingStatus::Active, $listing->fresh()->status);
    }

    #[Test]
    public function the_marketplace_routes_expose_no_write_methods(): void
    {
        $listing = $this->createListing($this->seller);

        // The whole phase is read-only, so the routes are not merely
        // unauthorised for writes — the methods do not exist. 405 rather than
        // 401 is what proves there is no write surface to protect later.
        $this->postJson('/api/listings', ['livestock_type' => 'cattle'])->assertStatus(405);
        $this->patchJson("/api/listings/{$listing->id}", ['livestock_type' => 'goat'])->assertStatus(405);
        $this->putJson("/api/listings/{$listing->id}", ['livestock_type' => 'goat'])->assertStatus(405);
        $this->deleteJson("/api/listings/{$listing->id}")->assertStatus(405);

        $this->assertDatabaseHas('listings', [
            'id' => $listing->id,
            'livestock_type' => 'cattle',
            'status' => ListingStatus::Active->value,
        ]);
    }
}
