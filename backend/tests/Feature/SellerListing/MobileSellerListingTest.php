<?php

namespace Tests\Feature\SellerListing;

use App\Enums\ListingStatus;
use App\Enums\UserRole;
use App\Models\Listing;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
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

    #[Test]
    public function a_buyer_cannot_manage_listings(): void
    {
        $this->store([], $this->mobileToken($this->buyer))
            ->assertForbidden();

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->buyer))
            ->getJson('/api/seller/listings')
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
    public function the_age_value_is_validated_as_an_integer(): void
    {
        // The column is `decimal(5,1)`, but the contract says `integer`, and the
        // contract is what a client is held to. Asserted explicitly so that
        // loosening the rule to match the column cannot pass unnoticed.
        $this->store(['age_value' => 8.5, 'age_unit' => 'month'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('age_value');
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
            // not asserted by value: the column is uncast, so it reads back as
            // `30` on SQLite and `30.0` on MySQL, which is the divergence the
            // mobile model already handles.
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
            ->assertJsonPath('data.status', ListingStatus::Pending->value);

        $this->assertDatabaseHas('listings', [
            'id' => $listing->id,
            'status' => ListingStatus::Pending->value,
        ]);
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

    // ---------------------------------------------------------------- delete

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
            ],
            $sellerRoutes,
        );
    }
}
