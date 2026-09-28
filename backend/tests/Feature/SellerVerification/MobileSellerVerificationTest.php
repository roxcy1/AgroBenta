<?php

namespace Tests\Feature\SellerVerification;

use App\Enums\SellerCapability;
use App\Enums\SellerVerificationStatus;
use App\Enums\UserRole;
use App\Models\SellerVerification;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Mobile seller verification — `POST /api/seller-verification` and
 * `GET /api/seller-verification/me`.
 *
 * Four properties are being defended, in order of how expensive they are to get
 * wrong.
 *
 * 1. Submitting grants nothing. A buyer who submits is still a buyer, and the
 *    only way to reach `seller_capability = seller` is an administrator
 *    approving the record. If a test here ever fails because a buyer became a
 *    seller, that is a critical defect, not a test to be relaxed.
 * 2. Authority is not client-writable. `user_id`, `status` and
 *    `seller_capability` are all rejected with a 422 rather than dropped, so a
 *    client cannot file against another account, self-approve, or backdate a
 *    record to win the "most recent" ordering.
 * 3. Resubmission creates history. A rejected record is never mutated back to
 *    `submitted`.
 * 4. Confidentiality. The response is the caller's own data and nothing else —
 *    no `reviewer`, no `seller.email`, no other user's record.
 */
class MobileSellerVerificationTest extends TestCase
{
    use RefreshDatabase;

    private User $buyer;

    private User $otherBuyer;

    protected function setUp(): void
    {
        parent::setUp();

        $this->buyer = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
            'name' => 'Ana Reyes',
            'email' => 'ana@agrobenta.test',
        ]);

        $this->otherBuyer = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
            'name' => 'Someone Else',
            'email' => 'other@agrobenta.test',
        ]);
    }

    private function mobileToken(User $user): string
    {
        return $user->createToken('mobile', ['mobile'])->plainTextToken;
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function createVerification(User $user, array $overrides = []): SellerVerification
    {
        return SellerVerification::create(array_merge([
            'user_id' => $user->id,
            'business_name' => 'Reyes Livestock',
            'business_location' => 'Mabalacat, Pampanga',
            'business_description' => 'Family cattle farm.',
            'id_document_ref' => 'ID-1234567',
            'status' => SellerVerificationStatus::Submitted,
            'admin_note' => null,
            'reviewed_by' => null,
            'reviewed_at' => null,
            'submitted_at' => now(),
        ], $overrides));
    }

    /**
     * @return array<string, mixed>
     */
    private function payload(array $overrides = []): array
    {
        return array_merge([
            'business_name' => 'Reyes Livestock',
            'business_location' => 'Mabalacat, Pampanga',
            'business_description' => 'Family cattle farm since 1998.',
            'id_document_ref' => 'ID-1234567',
        ], $overrides);
    }

    // -------------------------------------------------------------------
    // Submission
    // -------------------------------------------------------------------

    #[Test]
    public function a_buyer_can_submit_a_verification(): void
    {
        $response = $this->withToken($this->mobileToken($this->buyer))
            ->postJson('/api/seller-verification', $this->payload());

        $response->assertCreated()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.status', SellerVerificationStatus::Submitted->value)
            ->assertJsonPath('data.business_name', 'Reyes Livestock')
            ->assertJsonPath('data.business_location', 'Mabalacat, Pampanga')
            ->assertJsonPath('data.business_description', 'Family cattle farm since 1998.')
            ->assertJsonPath('data.id_document_ref', 'ID-1234567');

        $this->assertNotNull($response->json('data.submitted_at'));
        $this->assertDatabaseHas('seller_verifications', [
            'user_id' => $this->buyer->id,
            'status' => SellerVerificationStatus::Submitted->value,
        ]);
    }

    #[Test]
    public function submission_does_not_grant_seller_capability(): void
    {
        $this->withToken($this->mobileToken($this->buyer))
            ->postJson('/api/seller-verification', $this->payload())
            ->assertCreated();

        // The whole point of the single-account model: the account is unchanged.
        $this->assertSame(
            SellerCapability::Buyer,
            $this->buyer->fresh()->seller_capability,
        );
    }

    #[Test]
    public function the_optional_business_fields_may_be_omitted(): void
    {
        $this->withToken($this->mobileToken($this->buyer))
            ->postJson('/api/seller-verification', [
                'business_name' => 'Only a name',
            ])
            ->assertCreated()
            ->assertJsonPath('data.business_name', 'Only a name')
            ->assertJsonPath('data.business_location', null)
            ->assertJsonPath('data.business_description', null)
            ->assertJsonPath('data.id_document_ref', null);
    }

    #[Test]
    public function a_business_name_is_required(): void
    {
        $this->withToken($this->mobileToken($this->buyer))
            ->postJson('/api/seller-verification', [
                'business_location' => 'Mabalacat, Pampanga',
            ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('business_name');
    }

    #[Test]
    public function field_length_limits_match_the_contract(): void
    {
        $this->withToken($this->mobileToken($this->buyer))
            ->postJson('/api/seller-verification', $this->payload([
                'business_name' => str_repeat('a', 256),
                'business_location' => str_repeat('b', 256),
                'business_description' => str_repeat('c', 2001),
                'id_document_ref' => str_repeat('d', 256),
            ]))
            ->assertUnprocessable()
            ->assertJsonValidationErrors([
                'business_name',
                'business_location',
                'business_description',
                'id_document_ref',
            ]);
    }

    // -------------------------------------------------------------------
    // Authority is not client-writable
    // -------------------------------------------------------------------

    #[Test]
    public function a_client_cannot_choose_which_account_the_record_belongs_to(): void
    {
        $this->withToken($this->mobileToken($this->buyer))
            ->postJson('/api/seller-verification', $this->payload([
                'user_id' => $this->otherBuyer->id,
            ]))
            ->assertUnprocessable()
            ->assertJsonValidationErrors('user_id');

        $this->assertDatabaseCount('seller_verifications', 0);
    }

    #[Test]
    public function a_client_cannot_submit_an_already_approved_record(): void
    {
        $this->withToken($this->mobileToken($this->buyer))
            ->postJson('/api/seller-verification', $this->payload([
                'status' => SellerVerificationStatus::Approved->value,
            ]))
            ->assertUnprocessable()
            ->assertJsonValidationErrors('status');

        $this->assertDatabaseCount('seller_verifications', 0);
    }

    #[Test]
    public function a_client_cannot_set_the_admin_note_or_the_reviewer(): void
    {
        $this->withToken($this->mobileToken($this->buyer))
            ->postJson('/api/seller-verification', $this->payload([
                'admin_note' => 'Pre-emptive approval.',
                'reviewed_by' => 1,
                'reviewed_at' => now()->toISOString(),
            ]))
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['admin_note', 'reviewed_by', 'reviewed_at']);
    }

    #[Test]
    public function a_client_cannot_backdate_its_submission(): void
    {
        // `submitted_at` orders the "most recent record" that the resubmission
        // rule depends on, so a client that could set it could make an old
        // record look like the current one.
        $this->withToken($this->mobileToken($this->buyer))
            ->postJson('/api/seller-verification', $this->payload([
                'submitted_at' => now()->subYear()->toISOString(),
            ]))
            ->assertUnprocessable()
            ->assertJsonValidationErrors('submitted_at');
    }

    #[Test]
    public function a_client_cannot_grant_itself_seller_capability(): void
    {
        $this->withToken($this->mobileToken($this->buyer))
            ->postJson('/api/seller-verification', $this->payload([
                'seller_capability' => SellerCapability::Seller->value,
                'role' => UserRole::Admin->value,
            ]))
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['seller_capability', 'role']);

        $this->assertSame(
            SellerCapability::Buyer,
            $this->buyer->fresh()->seller_capability,
        );
    }

    #[Test]
    public function an_approved_seller_may_not_submit_again(): void
    {
        $seller = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Seller,
        ]);

        $this->withToken($this->mobileToken($seller))
            ->postJson('/api/seller-verification', $this->payload())
            ->assertForbidden();

        $this->assertDatabaseCount('seller_verifications', 0);
    }

    // -------------------------------------------------------------------
    // Open verification and resubmission
    // -------------------------------------------------------------------

    #[Test]
    public function a_second_submission_is_refused_while_one_is_open(): void
    {
        $this->createVerification($this->buyer, [
            'status' => SellerVerificationStatus::Submitted,
        ]);

        $this->withToken($this->mobileToken($this->buyer))
            ->postJson('/api/seller-verification', $this->payload())
            ->assertStatus(409);

        // Refused, not duplicated: the one open record is untouched.
        $this->assertDatabaseCount('seller_verifications', 1);
    }

    #[Test]
    public function a_pending_review_verification_also_blocks_a_submission(): void
    {
        $this->createVerification($this->buyer, [
            'status' => SellerVerificationStatus::PendingReview,
        ]);

        $this->withToken($this->mobileToken($this->buyer))
            ->postJson('/api/seller-verification', $this->payload())
            ->assertStatus(409);

        $this->assertDatabaseCount('seller_verifications', 1);
    }

    #[Test]
    public function a_rejected_verification_may_be_resubmitted_as_a_new_record(): void
    {
        $rejected = $this->createVerification($this->buyer, [
            'status' => SellerVerificationStatus::Rejected,
            'admin_note' => 'The ID reference could not be verified.',
            'reviewed_by' => null,
            'reviewed_at' => now(),
            'submitted_at' => now()->subDays(3),
        ]);

        $this->withToken($this->mobileToken($this->buyer))
            ->postJson('/api/seller-verification', $this->payload([
                'business_name' => 'Reyes Livestock Trading',
            ]))
            ->assertCreated()
            ->assertJsonPath('data.status', SellerVerificationStatus::Submitted->value)
            ->assertJsonPath('data.business_name', 'Reyes Livestock Trading');

        // History preserved: two rows, and the rejected one is unchanged.
        $this->assertDatabaseCount('seller_verifications', 2);
        $this->assertSame(
            SellerVerificationStatus::Rejected,
            $rejected->fresh()->status,
            'A resubmission must never mutate the rejected record.',
        );
        $this->assertSame(
            'The ID reference could not be verified.',
            $rejected->fresh()->admin_note,
        );
    }

    #[Test]
    public function the_current_verification_is_the_most_recent_by_submission_time(): void
    {
        $this->createVerification($this->buyer, [
            'business_name' => 'First attempt',
            'status' => SellerVerificationStatus::Rejected,
            'submitted_at' => now()->subDays(10),
        ]);
        $this->createVerification($this->buyer, [
            'business_name' => 'Second attempt',
            'status' => SellerVerificationStatus::Submitted,
            'submitted_at' => now()->subDay(),
        ]);

        $this->withToken($this->mobileToken($this->buyer))
            ->getJson('/api/seller-verification/me')
            ->assertOk()
            ->assertJsonPath('data.business_name', 'Second attempt');
    }

    // -------------------------------------------------------------------
    // Reading status
    // -------------------------------------------------------------------

    #[Test]
    public function a_buyer_who_never_submitted_gets_a_not_found(): void
    {
        $this->withToken($this->mobileToken($this->buyer))
            ->getJson('/api/seller-verification/me')
            ->assertNotFound();
    }

    #[Test]
    public function the_status_endpoint_returns_the_admin_note_for_a_rejection(): void
    {
        $this->createVerification($this->buyer, [
            'status' => SellerVerificationStatus::Rejected,
            'admin_note' => 'Please provide a clearer ID document reference.',
            // A rejected record has necessarily been reviewed, so the fixture
            // carries the decision timestamp the admin reject path would write.
            'reviewed_at' => now(),
        ]);

        // The contract requires `admin_note` here so a rejected user can be told
        // why without the client inventing a reason.
        $this->withToken($this->mobileToken($this->buyer))
            ->getJson('/api/seller-verification/me')
            ->assertOk()
            ->assertJsonPath('data.status', SellerVerificationStatus::Rejected->value)
            ->assertJsonPath('data.admin_note', 'Please provide a clearer ID document reference.')
            ->assertJsonPath('data.reviewed_at', fn ($value) => $value !== null);
    }

    #[Test]
    public function a_buyer_cannot_read_another_buyers_verification(): void
    {
        $this->createVerification($this->otherBuyer, [
            'business_name' => 'Not Yours Farm',
        ]);

        // `/me` takes no id, so there is no path to another account's record.
        $this->withToken($this->mobileToken($this->buyer))
            ->getJson('/api/seller-verification/me')
            ->assertNotFound();
    }

    #[Test]
    public function the_status_response_omits_the_reviewer_and_the_seller_email(): void
    {
        $admin = User::factory()->create([
            'role' => UserRole::Admin,
            'seller_capability' => SellerCapability::Seller,
            'name' => 'Admin Person',
        ]);

        $this->createVerification($this->buyer, [
            'status' => SellerVerificationStatus::Rejected,
            'admin_note' => 'Rejected for review.',
            'reviewed_by' => $admin->id,
            'reviewed_at' => now(),
        ]);

        $data = $this->withToken($this->mobileToken($this->buyer))
            ->getJson('/api/seller-verification/me')
            ->assertOk()
            ->json('data');

        // F-08 and contract §8.1: no reviewer identity, no email address, and
        // nothing belonging to another account.
        $this->assertArrayNotHasKey('reviewer', $data);
        $this->assertArrayNotHasKey('seller', $data);
        $this->assertArrayNotHasKey('user_id', $data);
        $this->assertArrayNotHasKey('created_at', $data);
        $this->assertStringNotContainsString(
            'Admin Person',
            json_encode($data, JSON_THROW_ON_ERROR),
        );
        $this->assertStringNotContainsString(
            'ana@agrobenta.test',
            json_encode($data, JSON_THROW_ON_ERROR),
        );
    }

    // -------------------------------------------------------------------
    // Authentication
    // -------------------------------------------------------------------

    #[Test]
    public function submission_requires_authentication(): void
    {
        $this->postJson('/api/seller-verification', $this->payload())
            ->assertUnauthorized();
    }

    #[Test]
    public function reading_the_status_requires_authentication(): void
    {
        $this->getJson('/api/seller-verification/me')
            ->assertUnauthorized();
    }

    #[Test]
    public function an_admin_token_cannot_reach_the_mobile_verification_api(): void
    {
        // Administrators review in the Admin Web. A mobile-scoped route that an
        // admin token could call would invert the ability boundary the auth and
        // marketplace groups already enforce.
        $admin = User::factory()->create(['role' => UserRole::Admin]);

        $this->withToken($admin->createToken('admin', ['admin'])->plainTextToken)
            ->getJson('/api/seller-verification/me')
            ->assertForbidden();
    }
}
