<?php

namespace Tests\Feature\SellerVerification;

use App\Enums\SellerCapability;
use App\Enums\SellerVerificationDocumentType as DocType;
use App\Enums\SellerVerificationStatus;
use App\Enums\UserRole;
use App\Models\SellerVerification;
use App\Models\User;
use App\Services\SellerVerification\SellerVerificationDocumentService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Testing\TestResponse;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Seller verification documents — the government ID and selfie.
 *
 * Five properties, ordered by how expensive they are to get wrong.
 *
 * 1. Privacy. Documents live on a private disk; no response carries a path or
 *    a URL, and streaming is authenticated (owner) or administrator-only,
 *    with `Cache-Control: private, no-store` so nothing retains a copy.
 * 2. The files are really persisted. Submission is refused with a 422 until
 *    both documents are staged, and a successful submission moves them onto
 *    the record.
 * 3. Server-side validation. Type, size and the owning account are decided by
 *    the server, never by client-supplied fields.
 * 4. Independence of the two documents. One upload per type, replaced rather
 *    than accumulated; the selfie is never derived from the ID image.
 * 5. No privilege changes. Uploading or submitting grants nothing; only an
 *    administrator approving does.
 */
class SellerVerificationDocumentsTest extends TestCase
{
    use RefreshDatabase;

    private User $buyer;

    private User $otherBuyer;

    private User $admin;

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

        $this->admin = User::factory()->create([
            'role' => UserRole::Admin,
            'seller_capability' => SellerCapability::Buyer,
            'name' => 'Admin Person',
        ]);
    }

    private function mobileToken(User $user): string
    {
        return $user->createToken('mobile', ['mobile'])->plainTextToken;
    }

    private function adminToken(): string
    {
        return $this->admin
            ->createToken('admin', ['admin'])
            ->plainTextToken;
    }

    private function upload(
        User $user,
        DocType $type,
        ?UploadedFile $file = null,
    ): TestResponse {
        return $this
            ->withToken($this->mobileToken($user))
            ->post('/api/seller-verification/documents', [
                'type' => $type->value,
                'document' => $file ?? UploadedFile::fake()->image(
                    "{$type->value}.png",
                    20,
                    20,
                ),
            ]);
    }

    private function stageBoth(User $user): void
    {
        foreach (DocType::cases() as $type) {
            $this->upload($user, $type)->assertCreated();
        }
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function createVerification(
        User $user,
        array $overrides = [],
    ): SellerVerification {
        return SellerVerification::create(array_merge([
            'user_id' => $user->id,
            'business_name' => 'Reyes Livestock',
            'business_location' => 'Mabalacat, Pampanga',
            'business_description' => 'Family cattle farm.',
            'id_document_ref' => null,
            'status' => SellerVerificationStatus::Submitted,
            'admin_note' => null,
            'reviewed_by' => null,
            'reviewed_at' => null,
            'submitted_at' => now(),
        ], $overrides));
    }

    /**
     * Store a file directly on the fake disk and return its path, for the
     * fixture cases where submission is not the subject of the test.
     */
    private function putDocument(SellerVerification $verification, DocType $type): string
    {
        $path = sprintf(
            'verifications/%d/%s.jpg',
            $verification->getKey(),
            $type->value,
        );

        Storage::disk(SellerVerificationDocumentService::DISK)
            ->put($path, "bytes-for-{$type->value}");

        $verification->forceFill([$type->column() => $path])->save();

        return $path;
    }

    // -------------------------------------------------------------------
    // Upload
    // -------------------------------------------------------------------

    #[Test]
    public function a_buyer_can_upload_both_documents_and_no_path_is_returned(): void
    {
        foreach (DocType::cases() as $type) {
            $response = $this->upload($this->buyer, $type);

            $response->assertCreated()
                ->assertJsonPath('data.type', $type->value)
                ->assertJsonPath('data.uploaded', true);
        }

        $staging = sprintf('staging/%d', $this->buyer->id);
        $files = Storage::disk(SellerVerificationDocumentService::DISK)
            ->files($staging);

        $this->assertCount(2, $files);

        // The private location must not leave the server in any form.
        $body = json_encode($response->json(), JSON_THROW_ON_ERROR);
        $this->assertStringNotContainsString('staging', $body);
        $this->assertStringNotContainsString('storage', $body);
        $this->assertStringNotContainsString('path', $body);
    }

    #[Test]
    public function uploading_the_same_type_again_replaces_the_staged_file(): void
    {
        $this->upload($this->buyer, DocType::IdDocument)->assertCreated();
        $this->upload($this->buyer, DocType::IdDocument)->assertCreated();

        $files = Storage::disk(SellerVerificationDocumentService::DISK)
            ->files(sprintf('staging/%d', $this->buyer->id));

        $this->assertCount(
            1,
            $files,
            'A replacement must leave exactly one staged ID, not two.',
        );
                $this->assertStringEndsWith(
                    'id_document.png',
                    $files[0],
                );
    }

    #[Test]
    public function the_selfie_is_a_separate_upload_from_the_id(): void
    {
        $this->upload($this->buyer, DocType::IdDocument)->assertCreated();
        $this->upload($this->buyer, DocType::Selfie)->assertCreated();

        $files = Storage::disk(SellerVerificationDocumentService::DISK)
            ->files(sprintf('staging/%d', $this->buyer->id));

        $this->assertCount(2, $files);
        $this->assertNotSame($files[0], $files[1]);
    }

    #[Test]
    public function an_unknown_document_type_is_refused(): void
    {
        $this->withToken($this->mobileToken($this->buyer))
            ->post('/api/seller-verification/documents', [
                'type' => 'proof_of_address',
                'document' => UploadedFile::fake()->image('x.png', 10, 10),
            ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('type');
    }

    #[Test]
    public function a_file_that_is_not_an_allowed_image_is_refused(): void
    {
        $this->upload(
            $this->buyer,
            DocType::IdDocument,
            UploadedFile::fake()->create('passport.pdf', 64, 'application/pdf'),
        )
            ->assertUnprocessable()
            ->assertJsonValidationErrors('document');
    }

    #[Test]
    public function a_file_larger_than_five_megabytes_is_refused(): void
    {
        $this->upload(
            $this->buyer,
            DocType::Selfie,
            UploadedFile::fake()->create('huge.jpg', 5200, 'image/jpeg'),
        )
            ->assertUnprocessable()
            ->assertJsonValidationErrors('document');
    }

    #[Test]
    public function the_upload_body_is_an_allow_list(): void
    {
        $this->withToken($this->mobileToken($this->buyer))
            ->post('/api/seller-verification/documents', [
                'type' => DocType::IdDocument->value,
                'document' => UploadedFile::fake()->image('id.png', 10, 10),
                'user_id' => $this->otherBuyer->id,
                'path' => '../../.env',
                'status' => SellerVerificationStatus::Approved->value,
            ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['user_id', 'path', 'status']);
    }

    #[Test]
    public function uploading_requires_a_mobile_token(): void
    {
        $this->post('/api/seller-verification/documents', [
            'type' => DocType::IdDocument->value,
            'document' => UploadedFile::fake()->image('id.png', 10, 10),
        ])->assertUnauthorized();
    }

    #[Test]
    public function an_admin_token_cannot_reach_the_mobile_upload_route(): void
    {
        $this->withToken($this->adminToken())
            ->post('/api/seller-verification/documents', [
                'type' => DocType::IdDocument->value,
                'document' => UploadedFile::fake()->image('id.png', 10, 10),
            ])
            ->assertForbidden();
    }

    #[Test]
    public function an_approved_seller_may_not_upload_documents(): void
    {
        $seller = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Seller,
        ]);

        $this->upload($seller, DocType::IdDocument)->assertForbidden();

        $this->assertSame(
            [],
            Storage::disk(SellerVerificationDocumentService::DISK)
                ->files(sprintf('staging/%d', $seller->id)),
        );
    }

    #[Test]
    public function documents_may_not_be_uploaded_while_an_application_is_in_review(): void
    {
        $this->createVerification($this->buyer);

        $this->upload($this->buyer, DocType::Selfie)->assertStatus(409);
    }

    #[Test]
    public function a_staged_document_can_be_removed_before_submission(): void
    {
        $this->upload($this->buyer, DocType::Selfie)->assertCreated();

        $this->withToken($this->mobileToken($this->buyer))
            ->delete('/api/seller-verification/documents/selfie')
            ->assertOk();

        $this->assertSame(
            [],
            Storage::disk(SellerVerificationDocumentService::DISK)
                ->files(sprintf('staging/%d', $this->buyer->id)),
        );

        // Removing twice is a 404, not a repeated success.
        $this->withToken($this->mobileToken($this->buyer))
            ->delete('/api/seller-verification/documents/selfie')
            ->assertNotFound();
    }

    #[Test]
    public function one_account_cannot_remove_another_accounts_staged_document(): void
    {
        $this->upload($this->buyer, DocType::Selfie)->assertCreated();

        $this->withToken($this->mobileToken($this->otherBuyer))
            ->delete('/api/seller-verification/documents/selfie')
            ->assertNotFound();

        $this->assertNotEmpty(
            Storage::disk(SellerVerificationDocumentService::DISK)
                ->files(sprintf('staging/%d', $this->buyer->id)),
        );
    }

    // -------------------------------------------------------------------
    // Submission requires both documents
    // -------------------------------------------------------------------

    #[Test]
    public function submission_is_refused_when_no_documents_are_staged(): void
    {
        $this->withToken($this->mobileToken($this->buyer))
            ->postJson('/api/seller-verification', [
                'business_name' => 'Reyes Livestock',
            ])
            ->assertUnprocessable()
            ->assertJsonPath('message', 'Upload both required documents before submitting.')
            ->assertJsonValidationErrors(['id_document', 'selfie']);

        $this->assertDatabaseCount('seller_verifications', 0);
    }

    #[Test]
    public function submission_is_refused_when_only_the_id_was_staged(): void
    {
        $this->upload($this->buyer, DocType::IdDocument)->assertCreated();

        $this->withToken($this->mobileToken($this->buyer))
            ->postJson('/api/seller-verification', [
                'business_name' => 'Reyes Livestock',
            ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('selfie')
            ->assertJsonMissingValidationErrors('id_document');

        $this->assertDatabaseCount('seller_verifications', 0);
    }

    #[Test]
    public function submission_wins_the_document_check_before_the_open_check_order_does_not_matter(): void
    {
        // An open record is refused with 409 even when documents are missing:
        // the state rule is not something the client can talk past by skipping
        // an upload.
        $this->createVerification($this->buyer);

        $this->withToken($this->mobileToken($this->buyer))
            ->postJson('/api/seller-verification', [
                'business_name' => 'Reyes Livestock',
            ])
            ->assertStatus(409);
    }

    #[Test]
    public function a_successful_submission_moves_the_files_onto_the_record(): void
    {
        $this->stageBoth($this->buyer);

        $this->withToken($this->mobileToken($this->buyer))
            ->postJson('/api/seller-verification', [
                'business_name' => 'Reyes Livestock',
            ])
            ->assertCreated()
            ->assertJsonPath('data.has_id_document', true)
            ->assertJsonPath('data.has_selfie', true);

        $verification = SellerVerification::query()
            ->where('user_id', $this->buyer->id)
            ->firstOrFail();

        $disk = Storage::disk(SellerVerificationDocumentService::DISK);

        $this->assertNotNull($verification->id_document_path);
        $this->assertNotNull($verification->selfie_path);
        $this->assertStringStartsWith(
            "verifications/{$verification->id}/",
            $verification->id_document_path,
        );
        $this->assertTrue($disk->exists($verification->id_document_path));
        $this->assertTrue($disk->exists($verification->selfie_path));

        $this->assertSame(
            [],
            $disk->files(sprintf('staging/%d', $this->buyer->id)),
            'Promotion must empty the staging directory.',
        );

        // Never a URL in the record.
        $this->assertStringNotContainsString('http', $verification->id_document_path);
        $this->assertStringNotContainsString('http', $verification->selfie_path);
    }

    #[Test]
    public function a_resubmission_requires_fresh_documents(): void
    {
        $rejected = $this->createVerification($this->buyer, [
            'status' => SellerVerificationStatus::Rejected,
            'admin_note' => 'Blurry ID.',
            'reviewed_at' => now(),
            'submitted_at' => now()->subDays(3),
        ]);
        $this->putDocument($rejected, DocType::IdDocument);
        $this->putDocument($rejected, DocType::Selfie);

        // The old record's files belong to the old record; the new one starts
        // from nothing.
        $this->withToken($this->mobileToken($this->buyer))
            ->postJson('/api/seller-verification', ['business_name' => 'Retry Farm'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['id_document', 'selfie']);

        $this->stageBoth($this->buyer);

        $this->withToken($this->mobileToken($this->buyer))
            ->postJson('/api/seller-verification', ['business_name' => 'Retry Farm'])
            ->assertCreated();
    }

    // -------------------------------------------------------------------
    // Reading the documents
    // -------------------------------------------------------------------

    #[Test]
    public function the_owner_can_stream_their_own_documents(): void
    {
        $this->stageBoth($this->buyer);

        $this->withToken($this->mobileToken($this->buyer))
            ->postJson('/api/seller-verification', [
                'business_name' => 'Reyes Livestock',
            ])
            ->assertCreated();

        $response = $this
            ->withToken($this->mobileToken($this->buyer))
            ->get('/api/seller-verification/documents/id_document');

        $response->assertOk();

        $cache = $response->headers->get('Cache-Control', '');
        $this->assertStringContainsString('private', $cache);
        $this->assertStringContainsString('no-store', $cache);
        $this->assertSame('nosniff', $response->headers->get('X-Content-Type-Options'));

        $verification = SellerVerification::query()
            ->where('user_id', $this->buyer->id)
            ->firstOrFail();

        $this->assertNotEmpty($response->streamedContent());
        $this->assertSame(
            Storage::disk(SellerVerificationDocumentService::DISK)
                ->get($verification->id_document_path),
            $response->streamedContent(),
        );
    }

    #[Test]
    public function another_account_cannot_stream_your_documents(): void
    {
        $this->stageBoth($this->buyer);
        $this->withToken($this->mobileToken($this->buyer))
            ->postJson('/api/seller-verification', ['business_name' => 'Reyes Livestock'])
            ->assertCreated();

        // No id in the path: the record is resolved from the token, so a
        // second account simply has no record and gets 404.
        $this->withToken($this->mobileToken($this->otherBuyer))
            ->get('/api/seller-verification/documents/id_document')
            ->assertNotFound();
    }

    #[Test]
    public function a_buyer_without_a_record_gets_a_not_found_for_documents(): void
    {
        $this->withToken($this->mobileToken($this->buyer))
            ->get('/api/seller-verification/documents/selfie')
            ->assertNotFound();
    }

    #[Test]
    public function an_unknown_document_type_cannot_be_read(): void
    {
        $verification = $this->createVerification($this->buyer);
        $this->putDocument($verification, DocType::IdDocument);

        $this->withToken($this->mobileToken($this->buyer))
            ->get('/api/seller-verification/documents/proof_of_address')
            ->assertNotFound();
    }

    #[Test]
    public function a_legacy_record_with_no_files_answers_not_found(): void
    {
        $this->createVerification($this->buyer);

        $this->withToken($this->mobileToken($this->buyer))
            ->get('/api/seller-verification/documents/id_document')
            ->assertNotFound();
    }

    #[Test]
    public function an_administrator_can_stream_any_applicants_documents(): void
    {
        $verification = $this->createVerification($this->buyer);
        $path = $this->putDocument($verification, DocType::IdDocument);

        $response = $this
            ->withToken($this->adminToken())
            ->get("/api/admin/seller-verifications/{$verification->id}/documents/id_document");

        $response->assertOk();
        $this->assertSame(
            Storage::disk(SellerVerificationDocumentService::DISK)->get($path),
            $response->streamedContent(),
        );
        $this->assertStringContainsString(
            'no-store',
            $response->headers->get('Cache-Control', ''),
        );
    }

    #[Test]
    public function a_mobile_token_cannot_read_documents_through_the_admin_route(): void
    {
        $verification = $this->createVerification($this->buyer);
        $this->putDocument($verification, DocType::IdDocument);

        $this->withToken($this->mobileToken($this->buyer))
            ->get("/api/admin/seller-verifications/{$verification->id}/documents/id_document")
            ->assertForbidden();
    }

    #[Test]
    public function an_unknown_type_cannot_be_read_through_the_admin_route(): void
    {
        $verification = $this->createVerification($this->buyer);
        $this->putDocument($verification, DocType::IdDocument);

        $this->withToken($this->adminToken())
            ->get("/api/admin/seller-verifications/{$verification->id}/documents/drivers_license")
            ->assertNotFound();
    }

    #[Test]
    public function no_response_carries_the_storage_paths(): void
    {
        $verification = $this->createVerification($this->buyer);
        $this->putDocument($verification, DocType::IdDocument);
        $this->putDocument($verification, DocType::Selfie);

        $mobile = $this->withToken($this->mobileToken($this->buyer))
            ->getJson('/api/seller-verification/me')
            ->assertOk()
            ->json('data');

        $admin = $this->withToken($this->adminToken())
            ->getJson("/api/admin/seller-verifications/{$verification->id}")
            ->assertOk()
            ->json('data');

        foreach ([$mobile, $admin] as $payload) {
            $this->assertArrayNotHasKey('id_document_path', $payload);
            $this->assertArrayNotHasKey('selfie_path', $payload);
            $this->assertTrue($payload['has_id_document']);
            $this->assertTrue($payload['has_selfie']);
            $this->assertStringNotContainsString(
                'verifications/',
                json_encode($payload, JSON_THROW_ON_ERROR),
            );
        }
    }

    #[Test]
    public function uploading_documents_grants_no_capability(): void
    {
        $this->stageBoth($this->buyer);

        $this->assertSame(
            SellerCapability::Buyer,
            $this->buyer->fresh()->seller_capability,
        );
    }
}
