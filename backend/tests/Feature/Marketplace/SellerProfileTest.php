<?php

namespace Tests\Feature\Marketplace;

use App\Enums\ListingStatus;
use App\Enums\SellerCapability;
use App\Enums\UserRole;
use App\Models\Listing;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Testing\TestResponse;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Public seller profile — `GET /api/marketplace/sellers/{seller}` and
 * `GET /api/marketplace/sellers/{seller}/listings`.
 *
 * Two things are defended here. Functionally, the profile must describe exactly
 * the marketplace the buyer already sees: the summary count and the Listings
 * tab use the same visibility rules, so sold, inactive, pending, reconciled and
 * fully reserved inventory never appears. Confidentially, a public profile is
 * readable by any signed-in buyer, so the response must not carry the seller's
 * email, phone number, exact address or any verification document.
 */
class SellerProfileTest extends TestCase
{
    use RefreshDatabase;

    private User $seller;

    protected function setUp(): void
    {
        parent::setUp();

        $this->seller = User::factory()->seller()->create([
            'role' => UserRole::User,
            'name' => 'Joseph Basilad',
            'email' => 'joseph@agrobenta.test',
            'phone' => '09171234567',
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
            'location' => 'Barangay San Isidro, Trinidad, Bohol',
            'health_status' => 'healthy',
            'vaccination' => 'up_to_date',
            'short_description' => 'Healthy Angus bull',
            'additional_notes' => null,
            'photos' => [],
            'status' => ListingStatus::Active,
        ], $overrides));
    }

    private function profile(int $sellerId, ?string $token = null): TestResponse
    {
        return $this->withHeader(
            'Authorization',
            'Bearer '.($token ?? $this->mobileToken(User::factory()->create())),
        )->getJson("/api/marketplace/sellers/{$sellerId}");
    }

    /**
     * @param  array<string, mixed>  $query
     */
    private function listings(int $sellerId, array $query = [], ?string $token = null): TestResponse
    {
        $suffix = $query === [] ? '' : '?'.http_build_query($query);

        return $this->withHeader(
            'Authorization',
            'Bearer '.($token ?? $this->mobileToken(User::factory()->create())),
        )->getJson("/api/marketplace/sellers/{$sellerId}/listings{$suffix}");
    }

    /*
    |--------------------------------------------------------------------------
    | Authentication and ability
    |--------------------------------------------------------------------------
    */

    #[Test]
    public function a_guest_cannot_read_a_seller_profile_or_its_listings(): void
    {
        $this->getJson("/api/marketplace/sellers/{$this->seller->id}")
            ->assertUnauthorized();
        $this->getJson("/api/marketplace/sellers/{$this->seller->id}/listings")
            ->assertUnauthorized();
    }

    #[Test]
    public function a_token_without_the_mobile_ability_cannot_read_the_profile(): void
    {
        $token = User::factory()->create()->createToken('user_token', [])->plainTextToken;

        $this->profile($this->seller->id, $token)->assertForbidden();
        $this->listings($this->seller->id, [], $token)->assertForbidden();
    }

    #[Test]
    public function an_admin_token_cannot_reach_the_public_profile(): void
    {
        $admin = User::factory()->admin()->create();
        $token = $admin->createToken('admin_token', ['admin'])->plainTextToken;

        $this->profile($this->seller->id, $token)->assertForbidden();
        $this->listings($this->seller->id, [], $token)->assertForbidden();
    }

    /*
    |--------------------------------------------------------------------------
    | Profile fields and disclosure
    |--------------------------------------------------------------------------
    */

    #[Test]
    public function a_buyer_can_read_an_approved_sellers_public_profile(): void
    {
        $this->seller->update([
            'avatar_url' => 'https://cdn.example.test/avatar.jpg',
            'bio' => 'Third-generation cattle farmer in Trinidad.',
        ]);
        Carbon::setTestNow('2026-11-17 10:00:00');
        $this->createListing($this->seller);

        $this->profile($this->seller->id)
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.id', $this->seller->id)
            ->assertJsonPath('data.name', 'Joseph Basilad')
            ->assertJsonPath('data.avatar_url', 'https://cdn.example.test/avatar.jpg')
            ->assertJsonPath('data.bio', 'Third-generation cattle farmer in Trinidad.')
            ->assertJsonPath('data.is_verified', true)
            ->assertJsonPath('data.active_listings_count', 1)
            ->assertJsonPath('data.member_since', $this->seller->created_at?->toISOString())
            ->assertJsonMissingPath('data.email')
            ->assertJsonMissingPath('data.phone')
            ->assertJsonMissingPath('data.location')
            ->assertJsonMissingPath('data.role')
            ->assertJsonMissingPath('data.seller_capability');

        Carbon::setTestNow();
    }

    #[Test]
    public function the_public_location_drops_the_street_and_purok(): void
    {
        $this->seller->update([
            'location' => 'Purok 4, Barangay San Isidro, Trinidad, Bohol',
        ]);
        $this->createListing($this->seller);

        $response = $this->profile($this->seller->id)->assertOk();

        $response->assertJsonPath(
            'data.public_location',
            'Barangay San Isidro, Trinidad, Bohol',
        );
        $this->assertStringNotContainsString('Purok 4', $response->getContent());
    }

    #[Test]
    public function an_unparseable_legacy_location_is_withheld(): void
    {
        $this->seller->update(['location' => 'Somewhere near the highway, Bohol']);
        $this->createListing($this->seller);

        $response = $this->profile($this->seller->id)
            ->assertOk()
            ->assertJsonPath('data.public_location', null);

        $this->assertStringNotContainsString('Somewhere near the highway', $response->getContent());
    }

    #[Test]
    public function a_profile_without_an_avatar_or_bio_reports_nulls(): void
    {
        $this->createListing($this->seller);

        $this->profile($this->seller->id)
            ->assertOk()
            ->assertJsonPath('data.avatar_url', null)
            ->assertJsonPath('data.bio', null);
    }

    #[Test]
    public function verification_is_reported_only_for_an_approved_seller(): void
    {
        $unverified = User::factory()->create([
            'seller_capability' => SellerCapability::Buyer,
            'name' => 'Pending Seller',
        ]);
        $this->createListing($unverified);

        $this->profile($unverified->id)
            ->assertOk()
            ->assertJsonPath('data.is_verified', false);

        $this->profile($this->seller->id)
            ->assertOk()
            ->assertJsonPath('data.is_verified', true);
    }

    /*
    |--------------------------------------------------------------------------
    | Availability
    |--------------------------------------------------------------------------
    */

    #[Test]
    public function a_plain_buyer_with_no_listings_has_no_public_profile(): void
    {
        $buyer = User::factory()->create();

        $this->profile($buyer->id)->assertNotFound();
        $this->listings($buyer->id)->assertNotFound();
    }

    #[Test]
    public function an_unknown_seller_is_not_found(): void
    {
        $this->profile(999999)->assertNotFound();
        $this->listings(999999)->assertNotFound();
    }

    #[Test]
    public function a_non_numeric_seller_id_is_not_found(): void
    {
        $this->getJson('/api/marketplace/sellers/abc')
            ->assertNotFound();
    }

    #[Test]
    public function a_soft_deleted_seller_is_not_found(): void
    {
        $this->createListing($this->seller);
        $this->seller->delete();

        $this->profile($this->seller->id)->assertNotFound();
        $this->listings($this->seller->id)->assertNotFound();
    }

    /*
    |--------------------------------------------------------------------------
    | Listings
    |--------------------------------------------------------------------------
    */

    #[Test]
    public function the_active_count_and_listings_exclude_every_non_marketplace_state(): void
    {
        $visible = $this->createListing($this->seller);
        $this->createListing($this->seller, ['breed' => 'Draft', 'status' => ListingStatus::Draft]);
        $this->createListing($this->seller, ['breed' => 'Pending', 'status' => ListingStatus::Pending]);
        $this->createListing($this->seller, ['breed' => 'Sold', 'status' => ListingStatus::Sold]);
        $this->createListing($this->seller, ['breed' => 'Inactive', 'status' => ListingStatus::Inactive]);
        $this->createListing($this->seller, [
            'breed' => 'Reserved',
            'quantity' => 0,
            'total_quantity' => 3,
        ]);
        $this->createListing($this->seller, [
            'breed' => 'Reconciliation',
            'quantity' => 2,
            'total_quantity' => null,
            'inventory_reconciliation_required' => true,
            'legacy_quantity_snapshot' => 2,
        ]);

        $this->profile($this->seller->id)
            ->assertOk()
            ->assertJsonPath('data.active_listings_count', 1);

        $this->listings($this->seller->id)
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 1)
            ->assertJsonPath('data.listings.0.id', $visible->id);
    }

    #[Test]
    public function the_listings_page_returns_another_sellers_visible_inventory_only(): void
    {
        $otherSeller = User::factory()->seller()->create();
        $own = $this->createListing($this->seller);
        $this->createListing($otherSeller);

        $response = $this->listings($this->seller->id)
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 1)
            ->assertJsonPath('data.listings.0.id', $own->id);

        $this->assertStringNotContainsString(
            (string) $otherSeller->name,
            $response->getContent(),
        );
    }

    #[Test]
    public function the_listings_page_is_paginated_newest_first(): void
    {
        foreach (range(1, 3) as $index) {
            $listing = $this->createListing($this->seller, ['breed' => 'Breed '.$index]);
            $listing->forceFill(['created_at' => now()->addMinutes($index)])->save();
        }

        $first = $this->listings($this->seller->id, ['per_page' => 2])
            ->assertOk()
            ->assertJsonPath('data.pagination.current_page', 1)
            ->assertJsonPath('data.pagination.last_page', 2)
            ->assertJsonPath('data.pagination.per_page', 2)
            ->assertJsonPath('data.pagination.total', 3)
            ->assertJsonPath('data.listings.0.breed', 'Breed 3')
            ->assertJsonPath('data.listings.1.breed', 'Breed 2');

        $first->assertJsonMissingPath('data.listings.2');

        $this->listings($this->seller->id, ['per_page' => 2, 'page' => 2])
            ->assertOk()
            ->assertJsonPath('data.listings.0.breed', 'Breed 1');
    }

    #[Test]
    public function the_listings_page_caps_per_page_and_refuses_ownership_and_status_filters(): void
    {
        $this->createListing($this->seller);

        $this->listings($this->seller->id, ['per_page' => 51])
            ->assertStatus(422)
            ->assertJsonValidationErrors('per_page');

        $this->listings($this->seller->id, ['seller_id' => 999])
            ->assertStatus(422)
            ->assertJsonValidationErrors('seller_id');

        $this->listings($this->seller->id, ['status' => 'sold'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('status');
    }

    #[Test]
    public function search_narrows_the_sellers_visible_inventory_in_the_database(): void
    {
        $angus = $this->createListing($this->seller, ['breed' => 'Angus']);
        $this->createListing($this->seller, ['livestock_type' => 'goat', 'breed' => 'Boer']);

        $otherSeller = User::factory()->seller()->create();
        $this->createListing($otherSeller, ['breed' => 'Angus']);

        $this->listings($this->seller->id, ['search' => 'angus'])
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 1)
            ->assertJsonPath('data.listings.0.id', $angus->id);

        // The listing name fields include the species, so a category word
        // searches too.
        $this->listings($this->seller->id, ['search' => 'goat'])
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 1)
            ->assertJsonPath('data.listings.0.breed', 'Boer');
    }

    #[Test]
    public function search_never_reaches_a_non_visible_listing(): void
    {
        $this->createListing($this->seller, [
            'breed' => 'Hidden Angus',
            'status' => ListingStatus::Sold,
        ]);
        $this->createListing($this->seller, ['breed' => 'Hidden Angus', 'quantity' => 0]);

        $this->listings($this->seller->id, ['search' => 'hidden'])
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 0);
    }

    #[Test]
    public function a_category_filter_narrows_to_that_species_within_the_seller(): void
    {
        $this->createListing($this->seller, ['breed' => 'Angus']);
        $goat = $this->createListing($this->seller, [
            'livestock_type' => 'goat',
            'breed' => 'Boer',
        ]);

        $otherSeller = User::factory()->seller()->create();
        $this->createListing($otherSeller, ['livestock_type' => 'goat', 'breed' => 'Kiko']);

        $this->listings($this->seller->id, ['livestock_type' => 'goat'])
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 1)
            ->assertJsonPath('data.listings.0.id', $goat->id);
    }

    #[Test]
    public function the_listings_page_supports_every_documented_sort(): void
    {
        $oldest = $this->createListing($this->seller, [
            'breed' => 'Oldest',
            'asking_price' => 30000.00,
        ]);
        $oldest->forceFill(['created_at' => now()->subMinutes(3)])->save();

        $middle = $this->createListing($this->seller, [
            'breed' => 'Middle',
            'asking_price' => 10000.00,
        ]);
        $middle->forceFill(['created_at' => now()->subMinutes(2)])->save();

        $newest = $this->createListing($this->seller, [
            'breed' => 'Newest',
            'asking_price' => 20000.00,
        ]);
        $newest->forceFill(['created_at' => now()->subMinute()])->save();

        $this->listings($this->seller->id)
            ->assertOk()
            ->assertJsonPath('data.listings.0.id', $newest->id)
            ->assertJsonPath('data.listings.1.id', $middle->id)
            ->assertJsonPath('data.listings.2.id', $oldest->id);

        $this->listings($this->seller->id, ['sort' => 'oldest'])
            ->assertOk()
            ->assertJsonPath('data.listings.0.id', $oldest->id)
            ->assertJsonPath('data.listings.2.id', $newest->id);

        $this->listings($this->seller->id, ['sort' => 'price_asc'])
            ->assertOk()
            ->assertJsonPath('data.listings.0.id', $middle->id)
            ->assertJsonPath('data.listings.1.id', $newest->id)
            ->assertJsonPath('data.listings.2.id', $oldest->id);

        $this->listings($this->seller->id, ['sort' => 'price_desc'])
            ->assertOk()
            ->assertJsonPath('data.listings.0.id', $oldest->id)
            ->assertJsonPath('data.listings.1.id', $newest->id)
            ->assertJsonPath('data.listings.2.id', $middle->id);
    }

    #[Test]
    public function filters_and_sorting_still_paginate_over_the_whole_result_set(): void
    {
        foreach (range(1, 3) as $index) {
            $listing = $this->createListing($this->seller, [
                'breed' => 'Goat '.$index,
                'livestock_type' => 'goat',
                'asking_price' => 1000.00 * $index,
            ]);
            $listing->forceFill(['created_at' => now()->addMinutes($index)])->save();
        }
        $this->createListing($this->seller, ['breed' => 'Cattle']);

        $this->listings($this->seller->id, [
            'livestock_type' => 'goat',
            'sort' => 'price_asc',
            'per_page' => 2,
        ])
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 3)
            ->assertJsonPath('data.pagination.last_page', 2)
            ->assertJsonPath('data.listings.0.breed', 'Goat 1')
            ->assertJsonPath('data.listings.1.breed', 'Goat 2');

        $this->listings($this->seller->id, [
            'livestock_type' => 'goat',
            'sort' => 'price_asc',
            'per_page' => 2,
            'page' => 2,
        ])
            ->assertOk()
            ->assertJsonPath('data.listings.0.breed', 'Goat 3');
    }

    #[Test]
    public function an_unknown_sort_or_an_oversized_filter_is_refused(): void
    {
        $this->createListing($this->seller);

        $this->listings($this->seller->id, ['sort' => 'popular'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('sort');

        $this->listings($this->seller->id, ['search' => str_repeat('a', 256)])
            ->assertStatus(422)
            ->assertJsonValidationErrors('search');

        $this->listings($this->seller->id, ['livestock_type' => str_repeat('a', 256)])
            ->assertStatus(422)
            ->assertJsonValidationErrors('livestock_type');
    }

    #[Test]
    public function an_approved_seller_with_no_active_listings_still_has_a_profile(): void
    {
        $this->profile($this->seller->id)
            ->assertOk()
            ->assertJsonPath('data.active_listings_count', 0);

        $this->listings($this->seller->id)
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 0);
    }
}
