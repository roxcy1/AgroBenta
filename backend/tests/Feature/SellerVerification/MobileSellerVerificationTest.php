<?php

namespace Tests\Feature\SellerVerification;

use App\Enums\SellerCapability;
use App\Enums\SellerVerificationDocumentType;
use App\Enums\SellerVerificationStatus;
use App\Enums\UserRole;
use App\Models\SellerVerification;
use App\Models\User;
use App\Services\SellerVerification\SellerVerificationDocumentService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
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

        Storage::fake(SellerVerificationDocumentService::DISK);

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
            'phone' => '09171234567',
            'address' => 'Trinidad, Bohol',
            'business_name' => 'Reyes Livestock',
            'business_location' => 'Mabalacat, Pampanga',
            'business_description' => 'Family cattle farm.',
            'id_document_ref' => 'ID-1234567',
            'government_id_type' => 'philippine_national_id',
            'has_no_back_image' => false,
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
            'phone' => '09171234567',
            'address' => 'Trinidad, Bohol',
            'business_name' => 'Reyes Livestock',
            'business_location' => 'Mabalacat, Pampanga',
            'business_description' => 'Family cattle farm since 1998.',
            'id_document_ref' => 'ID-1234567',
            'government_id_type' => 'philippine_national_id',
            'has_no_back_image' => false,
        ], $overrides);
    }

    /**
     * Stage both required documents for [user] through the real upload route.
     *
     * Staging is a precondition of submission, so every test that expects a
     * 201 comes through here rather than writing files directly: the endpoint,
     * the validation and the storage layout are all exercised.
     */
    private function stageDocuments(User $user): void
    {
        $token = $this->mobileToken($user);

        foreach (SellerVerificationDocumentType::cases() as $type) {
            if (! $type->isRequired()) {
                continue;
            }

            $this->withToken($token)
                ->post('/api/seller-verification/documents', [
                    'type' => $type->value,
                    'document' => UploadedFile::fake()->image(
                        "{$type->value}.png",
                        10,
                        10,
                    ),
                ])
                ->assertCreated();
        }

        $this->withToken($token)
            ->post('/api/seller-verification/documents', [
                'type' => SellerVerificationDocumentType::IdDocumentBack->value,
                'document' => UploadedFile::fake()->image('id-back.png', 10, 10),
            ])
            ->assertCreated();
    }

    // -------------------------------------------------------------------
    // Submission
    // -------------------------------------------------------------------

    #[Test]
    public function a_buyer_can_submit_a_verification(): void
    {
        $this->stageDocuments($this->buyer);

        $response = $this->withToken($this->mobileToken($this->buyer))
            ->postJson('/api/seller-verification', $this->payload());

        $response->assertCreated()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.status', SellerVerificationStatus::Submitted->value)
            ->assertJsonPath('data.phone', '09171234567')
            ->assertJsonPath('data.address', 'Trinidad, Bohol')
            ->assertJsonPath('data.business_name', 'Reyes Livestock')
            ->assertJsonPath('data.business_location', 'Mabalacat, Pampanga')
            ->assertJsonPath('data.business_description', 'Family cattle farm since 1998.')
            ->assertJsonPath('data.id_document_ref', 'ID-1234567')
            ->assertJsonPath('data.has_id_document', true)
            ->assertJsonPath('data.has_selfie', true);

        $this->assertNotNull($response->json('data.submitted_at'));
        $this->assertDatabaseHas('seller_verifications', [
            'user_id' => $this->buyer->id,
            'status' => SellerVerificationStatus::Submitted->value,
            'phone' => '09171234567',
            'address' => 'Trinidad, Bohol',
        ]);

        // The submitted record preserves the applicant's values even if their
        // editable profile is changed after the application is filed.
        $this->buyer->update([
            'phone' => '09990000000',
            'location' => 'A different profile location',
        ]);
        $this->withToken($this->mobileToken($this->buyer))
            ->getJson('/api/seller-verification/me')
            ->assertOk()
            ->assertJsonPath('data.phone', '09171234567')
            ->assertJsonPath('data.address', 'Trinidad, Bohol');
    }

    #[Test]
    public function submission_does_not_grant_seller_capability(): void
    {
        $this->stageDocuments($this->buyer);

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
        $this->stageDocuments($this->buyer);

        $this->withToken($this->mobileToken($this->buyer))
            ->postJson('/api/seller-verification', [
                'phone' => '09171234567',
                'address' => 'Trinidad, Bohol',
                'business_name' => 'Only a name',
                'government_id_type' => 'philippine_national_id',
                'has_no_back_image' => false,
            ])
            ->assertCreated()
            ->assertJsonPath('data.business_name', 'Only a name')
            ->assertJsonPath('data.business_location', null)
            ->assertJsonPath('data.business_description', null)
            ->assertJsonPath('data.id_document_ref', null);
    }

    #[Test]
    public function a_business_name_is_optional(): void
    {
        $this->stageDocuments($this->buyer);

        $this->withToken($this->mobileToken($this->buyer))
            ->postJson('/api/seller-verification', [
                'phone' => '09171234567',
                'address' => 'Trinidad, Bohol',
                'business_location' => 'Mabalacat, Pampanga',
                'government_id_type' => 'philippine_national_id',
                'has_no_back_image' => false,
            ])
            ->assertCreated()
            ->assertJsonPath('data.business_name', null);
    }

    #[Test]
    public function field_length_limits_match_the_contract(): void
    {
        $this->withToken($this->mobileToken($this->buyer))
            ->postJson('/api/seller-verification', $this->payload([
                'phone' => str_repeat('1', 33),
                'address' => str_repeat('a', 192),
                'business_name' => str_repeat('a', 256),
                'business_location' => str_repeat('b', 256),
                'business_description' => str_repeat('c', 2001),
                'id_document_ref' => str_repeat('d', 256),
            ]))
            ->assertUnprocessable()
            ->assertJsonValidationErrors([
                'phone',
                'address',
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
    public function phone_and_address_are_required_for_a_new_verification_snapshot(): void
    {
        $this->withToken($this->mobileToken($this->buyer))
            ->postJson('/api/seller-verification', [
                'business_name' => 'Reyes Livestock',
            ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['phone', 'address']);

        $this->assertDatabaseCount('seller_verifications', 0);
    }

    #[Test]
    public function legacy_verification_records_keep_nullable_contact_snapshots(): void
    {
        $verification = $this->createVerification($this->buyer, [
            'phone' => null,
            'address' => null,
        ]);

        $this->withToken($this->mobileToken($this->buyer))
            ->getJson('/api/seller-verification/me')
            ->assertOk()
            ->assertJsonPath('data.phone', null)
            ->assertJsonPath('data.address', null);

        $this->assertDatabaseHas('seller_verifications', [
            'id' => $verification->id,
            'phone' => null,
            'address' => null,
        ]);
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

        $this->stageDocuments($this->buyer);

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
