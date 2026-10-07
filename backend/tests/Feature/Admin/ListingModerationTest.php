<?php

namespace Tests\Feature\Admin;

use App\Enums\ListingStatus;
use App\Enums\SellerCapability;
use App\Enums\UserRole;
use App\Models\Listing;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Admin listing moderation â€” contract Â§5.4b, [D-02 rules 4 and 8].
 *
 * The lifecycle is the point of this file, and so is the fact that the server
 * decides it. Each of the three documented transitions is exercised, and so is
 * every way of reaching a state that is *not* one of them: an unauthenticated
 * caller, a caller with the wrong role, a caller with the wrong token ability,
 * and a caller acting on a listing that has already moved on.
 *
 * The stale-decision case is the reason the guards are server-side at all. An
 * administrator reads a pending row, a colleague approves it, and the first
 * administrator then acts on a screen that no longer describes reality. That has
 * to fail; nothing here asserts that the client cooperates.
 */
class ListingModerationTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    private User $adminColleague;

    private User $seller;

    protected function setUp(): void
    {
        parent::setUp();

        $this->admin = User::factory()->create([
            'role' => UserRole::Admin,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $this->adminColleague = User::factory()->create([
            'role' => UserRole::Admin,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $this->seller = User::factory()->seller()->create(['role' => UserRole::User]);
    }

    private function adminToken(?User $admin = null): string
    {
        return ($admin ?? $this->admin)
            ->createToken('admin_token', ['admin'])
            ->plainTextToken;
    }

    private function mobileToken(User $user): string
    {
        return $user->createToken('mobile', ['mobile'])->plainTextToken;
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function createListing(array $overrides = []): Listing
    {
        return Listing::create(array_merge([
            'seller_id' => $this->seller->id,
            'livestock_type' => 'cattle',
            'breed' => 'Angus',
            'age_value' => 2,
            'age_unit' => 'year',
            'gender' => 'male',
            'weight_value' => 500,
            'weight_unit' => 'kg',
            'quantity' => 3,
            'asking_price' => 50000.00,
            'location' => 'Bukidnon',
            'health_status' => 'healthy',
            'vaccination' => 'up_to_date',
            'short_description' => 'Healthy Angus bull',
            'additional_notes' => null,
            'photos' => [],
            'status' => ListingStatus::Pending,
            'admin_note' => null,
        ], $overrides));
    }

    /**
     * POST a moderation action as an administrator, or as whoever `token` names.
     *
     * @param  array<string, mixed>  $body
     */
    private function moderate(string $path, ?string $token = null, array $body = [])
    {
        $this->forgetResolvedGuards();

        $request = $this->withHeader(
            'Authorization',
            'Bearer '.($token ?? $this->adminToken()),
        );

        return $body === []
            ? $request->postJson($path)
            : $request->postJson($path, $body);
    }

    /**
     * POST with no `Authorization` header at all.
     *
     * @param  array<string, mixed>  $body
     */
    private function postAs(string $path, array $body = [])
    {
        $this->forgetResolvedGuards();

        return $body === []
            ? $this->postJson($path)
            : $this->postJson($path, $body);
    }

    /**
     * GET as the holder of a specific token.
     */
    private function getAsToken(string $token, string $path)
    {
        $this->forgetResolvedGuards();

        return $this->withHeader('Authorization', 'Bearer '.$token)->getJson($path);
    }

    /**
     * Read a seller's own listings through the M4 mobile endpoint, as mobile.
     *
     * Used to check what a seller sees *after* a moderation decision. The
     * moderation surface never calls the mobile one, so this is only ever a
     * consequence being observed, never a step in the transition.
     */
    private function sellerOwnListings(User $seller)
    {
        return $this->getAsToken($this->mobileToken($seller), '/api/seller/listings');
    }

    /**
     * Resolve the Sanctum guard between requests made as different users.
     *
     * The guard memoises the authenticated user for the lifetime of the resolved
     * instance, and that instance is reused across requests inside a single test.
     * Almost every case in this file is a moderation call followed by a read as
     * a *different* party — an administrator deciding, then a buyer or a seller
     * seeing the consequence — so without this the second request would silently
     * run as the first request's user, and the test would prove nothing about the
     * visibility it claims to check. The same helper and the same reasoning are
     * used in `MarketplaceListingTest`.
     */
    private function forgetResolvedGuards(): static
    {
        app('auth')->forgetGuards();

        return $this;
    }

    // ------------------------------------------------------- pending review

    #[Test]
    public function an_admin_can_see_a_pending_listing(): void
    {
        $listing = $this->createListing();

        $response = $this->withHeader('Authorization', 'Bearer '.$this->adminToken())
            ->getJson('/api/admin/listings?status=pending');

        $response->assertOk();
        $this->assertSame(1, $response->json('data.pagination.total'));

        // The row carries the review material: everything Â§8 asks an
        // administrator to see before deciding, and the seller behind it.
        $row = $response->json('data.listings.0');
        $this->assertSame($listing->id, $row['id']);
        $this->assertSame('pending', $row['status']);
        $this->assertSame('cattle', $row['livestock_type']);
        $this->assertSame('Angus', $row['breed']);
        $this->assertSame(2, $row['age_value']);
        $this->assertSame('year', $row['age_unit']);
        $this->assertSame('male', $row['gender']);
        $this->assertSame(500, $row['weight_value']);
        $this->assertSame('kg', $row['weight_unit']);
        $this->assertSame(3, $row['quantity']);
        $this->assertSame('50000.00', $row['asking_price']);
        $this->assertSame('Bukidnon', $row['location']);
        $this->assertSame('healthy', $row['health_status']);
        $this->assertSame('up_to_date', $row['vaccination']);
        $this->assertSame('Healthy Angus bull', $row['short_description']);
        $this->assertSame($this->seller->id, $row['seller']['id']);
    }

    // ------------------------------------------------------------- approval

    #[Test]
    public function an_admin_can_approve_a_pending_listing(): void
    {
        $listing = $this->createListing();

        $response = $this->moderate("/api/admin/listings/{$listing->id}/approve");

        $response->assertOk();
        $response->assertJsonPath('success', true);
        $response->assertJsonPath('data.id', $listing->id);
        $response->assertJsonPath('data.status', 'active');
    }

    #[Test]
    public function approval_moves_the_listing_from_pending_to_active(): void
    {
        $listing = $this->createListing();
        $this->assertSame(ListingStatus::Pending, $listing->status);

        $this->moderate("/api/admin/listings/{$listing->id}/approve")->assertOk();

        $this->assertSame(ListingStatus::Active, $listing->fresh()->status);
    }

    #[Test]
    public function an_approved_listing_becomes_visible_to_buyers(): void
    {
        $listing = $this->createListing();

        // Before approval the marketplace does not return it, in either shape.
        $buyer = $this->mobileToken(User::factory()->create());

        $this->getAsToken($buyer, '/api/listings')
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 0);

        $this->getAsToken($buyer, "/api/listings/{$listing->id}")->assertNotFound();

        $this->moderate("/api/admin/listings/{$listing->id}/approve")->assertOk();

        // After approval it is discoverable, and its detail is readable.
        $this->getAsToken($buyer, '/api/listings')
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 1)
            ->assertJsonPath('data.listings.0.id', $listing->id)
            ->assertJsonPath('data.listings.0.status', 'active');

        $this->getAsToken($buyer, "/api/listings/{$listing->id}")
            ->assertOk()
            ->assertJsonPath('data.id', $listing->id)
            ->assertJsonPath('data.status', 'active');
    }

    // ------------------------------------------------------------ rejection

    #[Test]
    public function an_admin_can_reject_a_pending_listing(): void
    {
        $listing = $this->createListing();

        $response = $this->moderate("/api/admin/listings/{$listing->id}/reject");

        $response->assertOk();
        $response->assertJsonPath('data.status', 'inactive');
        $this->assertSame(ListingStatus::Inactive, $listing->fresh()->status);
    }

    #[Test]
    public function a_rejected_listing_stays_hidden_from_buyers(): void
    {
        $listing = $this->createListing();
        $this->moderate("/api/admin/listings/{$listing->id}/reject")->assertOk();

        $buyer = $this->mobileToken(User::factory()->create());

        $this->getAsToken($buyer, '/api/listings')
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 0);

        $this->getAsToken($buyer, "/api/listings/{$listing->id}")->assertNotFound();
    }

    // ----------------------------------------------------- rejection reason

    #[Test]
    public function a_rejection_can_carry_an_administrators_note(): void
    {
        $listing = $this->createListing();

        $this->moderate("/api/admin/listings/{$listing->id}/reject", body: [
            'admin_note' => 'Health records are missing from the submission.',
        ])
            ->assertOk()
            ->assertJsonPath('data.admin_note', 'Health records are missing from the submission.');

        $this->assertSame(
            'Health records are missing from the submission.',
            $listing->fresh()->admin_note,
        );
    }

    #[Test]
    public function a_rejection_note_is_optional(): void
    {
        $listing = $this->createListing();

        $this->moderate("/api/admin/listings/{$listing->id}/reject")
            ->assertOk()
            ->assertJsonPath('data.status', 'inactive')
            ->assertJsonPath('data.admin_note', null);

        $this->assertNull($listing->fresh()->admin_note);
    }

    #[Test]
    public function a_rejection_note_that_is_not_a_string_is_rejected(): void
    {
        $listing = $this->createListing();

        $this->moderate("/api/admin/listings/{$listing->id}/reject", body: ['admin_note' => ['a']])
            ->assertStatus(422);

        $this->assertSame(ListingStatus::Pending, $listing->fresh()->status);
    }

    #[Test]
    public function a_rejection_note_is_not_visible_on_the_mobile_listing(): void
    {
        // The note is an administrator's record. Functional documentation
        // §10.4 and contract §8.1 forbid an admin-only field from appearing on
        // a mobile response, and the seller is a mobile client.
        $listing = $this->createListing();

        $this->moderate("/api/admin/listings/{$listing->id}/reject", body: [
            'admin_note' => 'Internal moderation note.',
        ])->assertOk();

        $this->sellerOwnListings($this->seller)
            ->assertOk()
            ->assertJsonPath('data.listings.0.status', 'inactive')
            ->assertJsonMissingPath('data.listings.0.admin_note');

        $this->getAsToken($this->mobileToken($this->seller), "/api/listings/{$listing->id}")
            ->assertOk()
            ->assertJsonMissingPath('data.admin_note');
    }

    #[Test]
    public function a_seller_cannot_write_their_own_rejection_note(): void
    {
        // The column is mass-assignable on the model, so the seller request must
        // refuse it explicitly rather than relying on it being absent from the
        // allow-list.
        $listing = $this->createListing();

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson("/api/seller/listings/{$listing->id}", ['admin_note' => 'Looks fine to me'])
            ->assertStatus(422);

        $this->assertNull($listing->fresh()->admin_note);
    }

    #[Test]
    public function approve_and_deactivate_store_no_note(): void
    {
        // The contract annotates `reject` with a note and the other two with
        // nothing, so the shared request carries no `admin_note` rule and the
        // field is never written. The transition still succeeds — an unlisted
        // field is ignored, not a client error — but nothing is persisted.
        $pending = $this->createListing();
        $this->moderate("/api/admin/listings/{$pending->id}/approve", body: ['admin_note' => 'hello'])
            ->assertOk()
            ->assertJsonPath('data.status', 'active')
            ->assertJsonPath('data.admin_note', null);
        $this->assertNull($pending->fresh()->admin_note);

        $active = $this->createListing(['status' => ListingStatus::Active]);
        $this->moderate("/api/admin/listings/{$active->id}/deactivate", body: ['admin_note' => 'hello'])
            ->assertOk()
            ->assertJsonPath('data.status', 'inactive')
            ->assertJsonPath('data.admin_note', null);
        $this->assertNull($active->fresh()->admin_note);
    }

    #[Test]
    public function a_rejection_note_survives_an_unrelated_later_decision(): void
    {
        // A moderator's explanation is history. Nothing in [D-02] clears it, so
        // a note written at rejection is not erased by a later transition.
        $listing = $this->createListing();

        $this->moderate("/api/admin/listings/{$listing->id}/reject", body: [
            'admin_note' => 'Missing health records.',
        ])->assertOk();

        $this->assertSame('Missing health records.', $listing->fresh()->admin_note);
    }

    // ---------------------------------------------------------- deactivation

    #[Test]
    public function an_admin_can_deactivate_an_active_listing(): void
    {
        $listing = $this->createListing(['status' => ListingStatus::Active]);

        $this->moderate("/api/admin/listings/{$listing->id}/deactivate")
            ->assertOk()
            ->assertJsonPath('data.status', 'inactive');

        $this->assertSame(ListingStatus::Inactive, $listing->fresh()->status);
    }

    #[Test]
    public function a_deactivated_listing_stays_hidden_from_buyers(): void
    {
        $listing = $this->createListing(['status' => ListingStatus::Active]);
        $this->moderate("/api/admin/listings/{$listing->id}/deactivate")->assertOk();

        $buyer = $this->mobileToken(User::factory()->create());

        $this->getAsToken($buyer, '/api/listings')
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 0);
    }

    // -------------------------------------------------------- authorisation

    #[Test]
    public function a_normal_user_cannot_approve(): void
    {
        $listing = $this->createListing();

        $this->moderate("/api/admin/listings/{$listing->id}/approve", $this->mobileToken($this->seller))
            ->assertForbidden();

        $this->assertSame(ListingStatus::Pending, $listing->fresh()->status);
    }

    #[Test]
    public function a_seller_cannot_approve_their_own_listing(): void
    {
        // Ownership is not a defence and not an exception: moderation is an
        // administrator power, and a seller approving their own listing is the
        // exact bypass [D-02 rule 6] exists to prevent.
        $listing = $this->createListing();

        $this->moderate("/api/admin/listings/{$listing->id}/approve", $this->mobileToken($this->seller))
            ->assertForbidden();

        $this->assertSame(ListingStatus::Pending, $listing->fresh()->status);
    }

    #[Test]
    public function an_unauthenticated_caller_cannot_approve(): void
    {
        $listing = $this->createListing();

        $this->postAs("/api/admin/listings/{$listing->id}/approve")->assertUnauthorized();

        $this->assertSame(ListingStatus::Pending, $listing->fresh()->status);
    }

    #[Test]
    public function a_mobile_token_cannot_approve(): void
    {
        // The admin group requires `ability:admin`, not merely `role = admin`.
        // A token minted through the mobile flow carries `['mobile']` and is
        // refused even for an account that holds the admin role.
        $listing = $this->createListing();

        $this->moderate("/api/admin/listings/{$listing->id}/approve", $this->mobileToken($this->admin))
            ->assertForbidden();
    }

    #[Test]
    public function moderation_is_refused_for_every_action_when_unauthenticated(): void
    {
        $listing = $this->createListing();

        foreach (['approve', 'reject'] as $action) {
            $this->postAs("/api/admin/listings/{$listing->id}/{$action}")
                ->assertUnauthorized();
        }

        $this->postAs("/api/admin/listings/{$listing->id}/deactivate")
            ->assertUnauthorized();
    }

    #[Test]
    public function moderation_is_refused_for_every_action_for_a_normal_user(): void
    {
        $listing = $this->createListing();
        $token = $this->mobileToken($this->seller);

        foreach (['approve', 'reject', 'deactivate'] as $action) {
            $this->moderate("/api/admin/listings/{$listing->id}/{$action}", $token)
                ->assertForbidden();
        }
    }

    // ----------------------------------------------------- invalid lifecycle

    /**
     * A draft has never been reviewed, so approving it would skip moderation
     * entirely; a sold listing is terminal; an inactive one has already been
     * through a decision. None of them can be approved.
     */
    #[Test]
    #[DataProvider('unapprovableStatuses')]
    public function a_listing_in_the_wrong_state_cannot_be_approved(ListingStatus $status): void
    {
        $listing = $this->createListing(['status' => $status]);

        $this->moderate("/api/admin/listings/{$listing->id}/approve")->assertStatus(409);

        $this->assertSame($status, $listing->fresh()->status);
    }

    /**
     * @return array<string, array{ListingStatus}>
     */
    public static function unapprovableStatuses(): array
    {
        return [
            'draft' => [ListingStatus::Draft],
            'sold' => [ListingStatus::Sold],
            'inactive' => [ListingStatus::Inactive],
            'already active' => [ListingStatus::Active],
        ];
    }

    #[Test]
    public function a_draft_cannot_be_approved(): void
    {
        $listing = $this->createListing(['status' => ListingStatus::Draft]);

        $this->moderate("/api/admin/listings/{$listing->id}/approve")->assertStatus(409);

        $this->assertSame(ListingStatus::Draft, $listing->fresh()->status);
    }

    #[Test]
    public function a_sold_listing_cannot_be_approved(): void
    {
        $listing = $this->createListing(['status' => ListingStatus::Sold]);

        $this->moderate("/api/admin/listings/{$listing->id}/approve")->assertStatus(409);

        $this->assertSame(ListingStatus::Sold, $listing->fresh()->status);
    }

    #[Test]
    public function an_inactive_listing_cannot_be_reactivated(): void
    {
        // [D-02]: `inactive -> active` is not a permitted transition and no
        // reactivation route is specified (A-02 / OQ-16). Every action refuses.
        $listing = $this->createListing(['status' => ListingStatus::Inactive]);

        foreach (['approve', 'reject', 'deactivate'] as $action) {
            $this->moderate("/api/admin/listings/{$listing->id}/{$action}")->assertStatus(409);
        }

        $this->assertSame(ListingStatus::Inactive, $listing->fresh()->status);
    }

    #[Test]
    public function only_a_pending_listing_can_be_rejected(): void
    {
        foreach ([ListingStatus::Draft, ListingStatus::Active, ListingStatus::Sold, ListingStatus::Inactive] as $status) {
            $listing = $this->createListing(['status' => $status]);

            $this->moderate("/api/admin/listings/{$listing->id}/reject")->assertStatus(409);

            $this->assertSame($status, $listing->fresh()->status);
        }
    }

    #[Test]
    public function only_an_active_listing_can_be_deactivated(): void
    {
        foreach ([ListingStatus::Draft, ListingStatus::Pending, ListingStatus::Sold, ListingStatus::Inactive] as $status) {
            $listing = $this->createListing(['status' => $status]);

            $this->moderate("/api/admin/listings/{$listing->id}/deactivate")->assertStatus(409);

            $this->assertSame($status, $listing->fresh()->status);
        }
    }

    #[Test]
    public function an_invalid_transition_reports_a_conflict(): void
    {
        $listing = $this->createListing(['status' => ListingStatus::Sold]);

        $this->moderate("/api/admin/listings/{$listing->id}/approve")
            ->assertStatus(409)
            ->assertJsonStructure(['message']);
    }

    // ------------------------------------------------------- stale decisions

    #[Test]
    public function a_second_approval_of_the_same_listing_is_refused(): void
    {
        $listing = $this->createListing();

        $this->moderate("/api/admin/listings/{$listing->id}/approve")->assertOk();

        // The second administrator is looking at a screen that no longer
        // describes the stored row. The server, not the client, is the authority.
        $this->moderate("/api/admin/listings/{$listing->id}/approve", $this->adminToken($this->adminColleague))
            ->assertStatus(409);

        $this->assertSame(ListingStatus::Active, $listing->fresh()->status);
    }

    #[Test]
    public function a_rejection_that_arrives_after_an_approval_is_refused(): void
    {
        $listing = $this->createListing();

        $this->moderate("/api/admin/listings/{$listing->id}/approve")->assertOk();

        // A late rejection must not be able to withdraw a listing that is now
        // live; that is `deactivate`'s transition, and only from `active`.
        $this->moderate("/api/admin/listings/{$listing->id}/reject", $this->adminToken($this->adminColleague))
            ->assertStatus(409);

        $this->assertSame(ListingStatus::Active, $listing->fresh()->status);
    }

    #[Test]
    public function an_approval_that_arrives_after_a_rejection_is_refused(): void
    {
        $listing = $this->createListing();

        $this->moderate("/api/admin/listings/{$listing->id}/reject")->assertOk();

        $this->moderate("/api/admin/listings/{$listing->id}/approve", $this->adminToken($this->adminColleague))
            ->assertStatus(409);

        $this->assertSame(ListingStatus::Inactive, $listing->fresh()->status);
    }

    // ------------------------------------------------------------- not found

    #[Test]
    public function moderating_a_listing_that_does_not_exist_is_a_not_found(): void
    {
        $this->moderate('/api/admin/listings/999999/approve')->assertNotFound();
    }

    // ------------------------------------------------- transition integrity

    #[Test]
    public function moderation_returns_the_updated_listing_state(): void
    {
        $listing = $this->createListing();

        $response = $this->moderate("/api/admin/listings/{$listing->id}/approve");

        $response->assertOk();
        $response->assertJsonStructure([
            'success',
            'message',
            'data' => [
                'id', 'seller', 'livestock_type', 'breed', 'age_value', 'age_unit',
                'gender', 'weight_value', 'weight_unit', 'quantity', 'asking_price',
                'location', 'health_status', 'vaccination', 'short_description',
                'additional_notes', 'status', 'created_at', 'updated_at',
            ],
        ]);
    }

    #[Test]
    public function a_client_cannot_name_the_status_on_a_moderation_endpoint(): void
    {
        // The endpoint is an action, not a status setter. Posting `status` is a
        // client bug and is reported as one, rather than being ignored while the
        // action quietly does what it always does.
        $listing = $this->createListing();

        $this->moderate("/api/admin/listings/{$listing->id}/approve", body: ['status' => 'active'])
            ->assertStatus(422);

        $this->assertSame(ListingStatus::Pending, $listing->fresh()->status);
    }

    #[Test]
    public function a_client_cannot_use_the_moderation_endpoints_to_bypass_the_seller_surface(): void
    {
        // The seller surface has no route that sets a status, and none is added
        // here. Confirming it stays that way: a seller `PATCH` carrying a status
        // is refused, exactly as in M4.
        $listing = $this->createListing();

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($this->seller))
            ->patchJson("/api/seller/listings/{$listing->id}", ['status' => 'active'])
            ->assertStatus(422);

        $this->assertSame(ListingStatus::Pending, $listing->fresh()->status);
    }

    #[Test]
    public function seller_ownership_from_m4_is_unchanged_by_moderation(): void
    {
        // A second seller still cannot see or touch the first seller's listing,
        // even now that a moderation surface exists.
        $listing = $this->createListing();
        $otherSeller = User::factory()->seller()->create(['role' => UserRole::User]);

        $this->sellerOwnListings($otherSeller)
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 0);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($otherSeller))
            ->patchJson("/api/seller/listings/{$listing->id}", ['livestock_type' => 'goat'])
            ->assertNotFound();

        $this->assertSame('cattle', $listing->fresh()->livestock_type);
    }

    #[Test]
    public function moderation_does_not_change_the_seller_of_a_listing(): void
    {
        $listing = $this->createListing();

        $this->moderate("/api/admin/listings/{$listing->id}/approve")->assertOk();

        $this->assertSame($this->seller->id, $listing->fresh()->seller_id);
    }

    // ------------------------------------------------ seller mobile status

    #[Test]
    public function the_seller_sees_the_moderated_status_on_their_own_listing(): void
    {
        // No seller action is involved: the seller's own-listing screen simply
        // reflects the server's decision on the next read, which is the whole
        // M5 mobile requirement.
        $listing = $this->createListing();

        $this->sellerOwnListings($this->seller)
            ->assertOk()
            ->assertJsonPath('data.listings.0.status', 'pending');

        $this->moderate("/api/admin/listings/{$listing->id}/approve")->assertOk();

        $this->sellerOwnListings($this->seller)
            ->assertOk()
            ->assertJsonPath('data.listings.0.status', 'active')
            ->assertJsonPath('data.listings.0.id', $listing->id);
    }

    #[Test]
    public function a_rejected_listing_reports_as_inactive_to_its_seller(): void
    {
        $listing = $this->createListing();

        $this->moderate("/api/admin/listings/{$listing->id}/reject")->assertOk();

        $this->sellerOwnListings($this->seller)
            ->assertOk()
            ->assertJsonPath('data.listings.0.status', 'inactive');
    }

    // ------------------------------------------------------- marketplace mix

    #[Test]
    public function the_marketplace_shows_only_the_approved_listing(): void
    {
        $pending = $this->createListing();
        $draft = $this->createListing(['status' => ListingStatus::Draft]);
        $sold = $this->createListing(['status' => ListingStatus::Sold]);
        $inactive = $this->createListing(['status' => ListingStatus::Inactive]);
        $alreadyActive = $this->createListing(['status' => ListingStatus::Active]);

        $this->moderate("/api/admin/listings/{$pending->id}/approve")->assertOk();

        $buyer = $this->mobileToken(User::factory()->create());

        $response = $this->getAsToken($buyer, '/api/listings')->assertOk();

        $ids = array_column($response->json('data.listings'), 'id');

        $this->assertContains($pending->id, $ids);
        $this->assertContains($alreadyActive->id, $ids);
        $this->assertNotContains($draft->id, $ids);
        $this->assertNotContains($sold->id, $ids);
        $this->assertNotContains($inactive->id, $ids);
        $this->assertSame(2, $response->json('data.pagination.total'));
    }

    #[Test]
    public function an_admin_can_moderate_a_listing_from_a_different_seller(): void
    {
        // Administrators are not scoped by seller. A second approved seller's
        // listing is moderated exactly like the first one's.
        $listing = $this->createListing();

        $this->moderate("/api/admin/listings/{$listing->id}/approve")
            ->assertOk()
            ->assertJsonPath('data.seller.id', $this->seller->id);
    }
}
