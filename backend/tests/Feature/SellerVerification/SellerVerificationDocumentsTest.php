<?php

namespace Tests\Feature\SellerVerification;

use App\Enums\GovernmentIdType;
use App\Enums\SellerCapability;
use App\Enums\SellerVerificationDocumentType as DocType;
use App\Enums\SellerVerificationStatus;
use App\Enums\UserRole;
use App\Models\SellerVerification;
use App\Models\User;
use App\Services\ActivityLogger;
use App\Services\SellerVerification\SellerVerificationDocumentService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;
use Illuminate\Testing\TestResponse;
use Mockery\MockInterface;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
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

    #[Test]
    public function seller_verifications_schema_has_contact_snapshots_and_document_path_columns(): void
    {
        $this->assertTrue(
            Schema::hasColumns('seller_verifications', [
                'phone',
                'address',
                'id_document_path',
                'id_document_front_path',
                'id_document_back_path',
                'government_id_type',
                'government_id_description',
                'has_no_back_image',
                'selfie_path',
            ]),
            'Document paths must have columns before submission can persist them.',
        );
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
        foreach ($this->requiredTypes() as $type) {
            $this->upload($user, $type)->assertCreated();
        }
        $this->upload($user, DocType::IdDocumentBack)->assertCreated();
    }

    /**
     * @return list<DocType>
     */
    private function requiredTypes(): array
    {
        return array_values(array_filter(
            DocType::cases(),
            fn (DocType $type): bool => $type->isRequired(),
        ));
    }

    private function submit(User $user, array $body = []): TestResponse
    {
        return $this->withToken($this->mobileToken($user))
            ->postJson('/api/seller-verification', array_merge([
                'phone' => '09171234567',
                'address' => 'Trinidad, Bohol',
                'government_id_type' => 'philippine_national_id',
                'has_no_back_image' => false,
            ], $body));
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
            'phone' => '09171234567',
            'address' => 'Trinidad, Bohol',
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
    public function a_buyer_can_upload_every_required_document_and_no_path_is_returned(): void
    {
        foreach ($this->requiredTypes() as $type) {
            $response = $this->upload($this->buyer, $type);

            $response->assertCreated()
                ->assertJsonPath('data.type', $type->value)
                ->assertJsonPath('data.uploaded', true);
        }

        $staging = sprintf('staging/%d', $this->buyer->id);
        $files = Storage::disk(SellerVerificationDocumentService::DISK)
            ->files($staging);

        $this->assertCount(3, $files);

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
                'type' => 'drivers_license',
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
        $this->submit($this->buyer, [
            'business_name' => 'Reyes Livestock',
        ])
            ->assertUnprocessable()
            ->assertJsonPath('message', 'Upload all required documents before submitting.')
            ->assertJsonValidationErrors(['id_document_front', 'id_document_back', 'selfie', 'proof_of_address'])
            ->assertJsonMissingValidationErrors('farm_photo');

        $this->assertDatabaseCount('seller_verifications', 0);
    }

    #[Test]
    public function submission_is_refused_when_only_the_id_was_staged(): void
    {
        $this->upload($this->buyer, DocType::IdDocumentFront)->assertCreated();

        $this->submit($this->buyer, [
            'business_name' => 'Reyes Livestock',
        ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['id_document_back', 'selfie', 'proof_of_address'])
            ->assertJsonMissingValidationErrors('id_document_front');

        $this->assertDatabaseCount('seller_verifications', 0);
    }

    #[Test]
    public function submission_wins_the_document_check_before_the_open_check_order_does_not_matter(): void
    {
        // An open record is refused with 409 even when documents are missing:
        // the state rule is not something the client can talk past by skipping
        // an upload.
        $this->createVerification($this->buyer);

        $this->submit($this->buyer, [
            'business_name' => 'Reyes Livestock',
        ])
            ->assertStatus(409);
    }

    #[Test]
    public function a_successful_submission_moves_the_files_onto_the_record(): void
    {
        $this->stageBoth($this->buyer);

        $this->submit($this->buyer, [
            'business_name' => 'Reyes Livestock',
        ])
            ->assertCreated()
            ->assertJsonPath('data.has_id_document', true)
            ->assertJsonPath('data.has_selfie', true);

        $verification = SellerVerification::query()
            ->where('user_id', $this->buyer->id)
            ->firstOrFail();

        $disk = Storage::disk(SellerVerificationDocumentService::DISK);

        $this->assertNotNull($verification->id_document_front_path);
        $this->assertNotNull($verification->id_document_back_path);
        $this->assertNotNull($verification->selfie_path);
        $this->assertStringStartsWith(
            "verifications/{$verification->id}/",
            $verification->id_document_front_path,
        );
        $this->assertTrue($disk->exists($verification->id_document_front_path));
        $this->assertTrue($disk->exists($verification->id_document_back_path));
        $this->assertTrue($disk->exists($verification->selfie_path));

        $this->assertSame(
            [],
            $disk->files(sprintf('staging/%d', $this->buyer->id)),
            'Promotion must empty the staging directory.',
        );

        // Never a URL in the record.
        $this->assertStringNotContainsString('http', $verification->id_document_front_path);
        $this->assertStringNotContainsString('http', $verification->selfie_path);
        $this->assertSame('philippine_national_id', $verification->government_id_type);
        $this->assertFalse($verification->has_no_back_image);
    }

    #[Test]
    public function a_front_only_id_requires_an_explicit_no_back_declaration(): void
    {
        foreach ([DocType::IdDocumentFront, DocType::Selfie, DocType::ProofOfAddress] as $type) {
            $this->upload($this->buyer, $type)->assertCreated();
        }

        $this->submit($this->buyer, ['has_no_back_image' => true])
            ->assertCreated()
            ->assertJsonPath('data.has_id_document_front', true)
            ->assertJsonPath('data.has_id_document_back', false)
            ->assertJsonPath('data.has_no_back_image', true);

        $verification = SellerVerification::query()->where('user_id', $this->buyer->id)->firstOrFail();
        $this->assertNull($verification->id_document_back_path);
    }

    #[Test]
    public function no_back_declaration_is_rejected_when_a_back_image_is_staged(): void
    {
        $this->stageBoth($this->buyer);

        $this->submit($this->buyer, ['has_no_back_image' => true])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('has_no_back_image');
    }

    #[Test]
    public function missing_back_image_without_declaration_is_rejected(): void
    {
        foreach ([DocType::IdDocumentFront, DocType::Selfie, DocType::ProofOfAddress] as $type) {
            $this->upload($this->buyer, $type)->assertCreated();
        }

        $this->submit($this->buyer, ['has_no_back_image' => false])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('id_document_back');
    }

    #[Test]
    public function every_supported_government_id_type_is_accepted_and_snapshotted(): void
    {
        foreach (GovernmentIdType::cases() as $index => $type) {
            $applicant = User::factory()->create([
                'role' => UserRole::User,
                'seller_capability' => SellerCapability::Buyer,
            ]);
            $this->stageBoth($applicant);
            $body = ['government_id_type' => $type->value];
            if ($type === GovernmentIdType::Others) {
                $body['government_id_description'] = 'Barangay ID';
            }

            $this->submit($applicant, $body)->assertCreated()
                ->assertJsonPath('data.government_id_type', $type->value);
            $verification = SellerVerification::query()->where('user_id', $applicant->id)->firstOrFail();
            $this->assertSame($type->value, $verification->government_id_type);
            $this->assertSame($type === GovernmentIdType::Others ? 'Barangay ID' : null, $verification->government_id_description);
        }
    }

    #[Test]
    public function government_id_type_and_others_description_are_required(): void
    {
        $this->stageBoth($this->buyer);
        $this->submit($this->buyer, ['government_id_type' => null])
            ->assertUnprocessable()->assertJsonValidationErrors('government_id_type');

        $this->submit($this->buyer, [
            'government_id_type' => 'others',
            'government_id_description' => null,
        ])->assertUnprocessable()->assertJsonValidationErrors('government_id_description');

        $this->submit($this->buyer, [
            'government_id_type' => 'passport',
        ])->assertUnprocessable()->assertJsonValidationErrors('government_id_type');
    }

    #[Test]
    public function a_failed_submission_removes_promoted_files(): void
    {
        $this->stageBoth($this->buyer);

        $this->mock(ActivityLogger::class, function (MockInterface $mock): void {
            $mock->shouldReceive('log')
                ->once()
                ->andThrow(new RuntimeException('Audit write failed.'));
        });

        $this->submit($this->buyer, [
            'business_name' => 'Reyes Livestock',
        ])
            ->assertStatus(500);

        $this->assertDatabaseCount('seller_verifications', 0);

        $disk = Storage::disk(SellerVerificationDocumentService::DISK);

        $this->assertSame(
            [],
            $disk->allFiles('verifications'),
            'A rolled-back submission must not leave its promoted files behind.',
        );
        $this->assertSame(
            [],
            $disk->allFiles(sprintf('staging/%d', $this->buyer->id)),
            'The failed submission must not leave files in staging either.',
        );
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
        $this->submit($this->buyer, ['business_name' => 'Retry Farm'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['id_document_front', 'id_document_back', 'selfie', 'proof_of_address']);

        $this->stageBoth($this->buyer);

        $this->submit($this->buyer, ['business_name' => 'Retry Farm'])
            ->assertCreated();
    }

    // -------------------------------------------------------------------
    // Reading the documents
    // -------------------------------------------------------------------

    #[Test]
    public function the_owner_can_stream_their_own_documents(): void
    {
        $this->stageBoth($this->buyer);

        $this->submit($this->buyer, [
            'business_name' => 'Reyes Livestock',
        ])
            ->assertCreated();

        $response = $this
            ->withToken($this->mobileToken($this->buyer))
            ->get('/api/seller-verification/documents/id_document_front');

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
                ->get($verification->id_document_front_path),
            $response->streamedContent(),
        );
    }

    #[Test]
    public function another_account_cannot_stream_your_documents(): void
    {
        $this->stageBoth($this->buyer);
        $this->submit($this->buyer, ['business_name' => 'Reyes Livestock'])
            ->assertCreated();

        // No id in the path: the record is resolved from the token, so a
        // second account simply has no record and gets 404.
        $this->withToken($this->mobileToken($this->otherBuyer))
            ->get('/api/seller-verification/documents/id_document_front')
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
            ->get('/api/seller-verification/documents/drivers_license')
            ->assertNotFound();
    }

    #[Test]
    public function a_legacy_record_with_no_files_answers_not_found(): void
    {
        $this->createVerification($this->buyer);

        $this->withToken($this->mobileToken($this->buyer))
            ->get('/api/seller-verification/documents/id_document_front')
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
    public function an_administrator_streams_the_correct_id_front_and_back_images(): void
    {
        $verification = $this->createVerification($this->buyer);
        $frontPath = $this->putDocument($verification, DocType::IdDocumentFront);
        $backPath = $this->putDocument($verification, DocType::IdDocumentBack);
        $disk = Storage::disk(SellerVerificationDocumentService::DISK);

        foreach ([
            'id_document_front' => $frontPath,
            'id_document_back' => $backPath,
        ] as $type => $path) {
            $response = $this->withToken($this->adminToken())
                ->get("/api/admin/seller-verifications/{$verification->id}/documents/{$type}")
                ->assertOk();

            $this->assertSame($disk->get($path), $response->streamedContent());
        }
    }

    #[Test]
    public function a_legacy_single_id_is_available_as_front_only(): void
    {
        $verification = $this->createVerification($this->buyer);
        $legacyPath = $this->putDocument($verification, DocType::IdDocument);
        $disk = Storage::disk(SellerVerificationDocumentService::DISK);

        $front = $this->withToken($this->adminToken())
            ->get("/api/admin/seller-verifications/{$verification->id}/documents/id_document_front")
            ->assertOk();
        $this->assertSame($disk->get($legacyPath), $front->streamedContent());

        $this->withToken($this->adminToken())
            ->get("/api/admin/seller-verifications/{$verification->id}/documents/id_document_back")
            ->assertNotFound();
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
            $this->assertTrue($payload['has_id_document_front']);
            $this->assertTrue($payload['has_selfie']);
            $this->assertStringNotContainsString(
                'verifications/',
                json_encode($payload, JSON_THROW_ON_ERROR),
            );
        }
    }

    // -------------------------------------------------------------------
    // Proof of address
    // -------------------------------------------------------------------

    #[Test]
    public function submission_is_refused_without_proof_of_address(): void
    {
        $this->upload($this->buyer, DocType::IdDocumentFront)->assertCreated();
        $this->upload($this->buyer, DocType::Selfie)->assertCreated();

        $this->submit($this->buyer)
            ->assertUnprocessable()
            ->assertJsonValidationErrors('proof_of_address')
            ->assertJsonMissingValidationErrors(['id_document_front', 'selfie']);
    }

    #[Test]
    public function proof_of_address_can_be_replaced_and_removed(): void
    {
        $disk = Storage::disk(SellerVerificationDocumentService::DISK);
        $staging = sprintf('staging/%d', $this->buyer->id);

        $this->upload($this->buyer, DocType::ProofOfAddress)->assertCreated();
        $this->upload($this->buyer, DocType::ProofOfAddress)->assertCreated();
        $this->assertCount(1, $disk->files($staging));

        $this->withToken($this->mobileToken($this->buyer))
            ->delete('/api/seller-verification/documents/proof_of_address')
            ->assertOk();
        $this->assertSame([], $disk->files($staging));
    }

    #[Test]
    public function proof_of_address_is_readable_by_the_owner_and_an_admin_only(): void
    {
        $verification = $this->createVerification($this->buyer);
        $this->putDocument($verification, DocType::ProofOfAddress);
        $url = "/admin/seller-verifications/{$verification->id}/documents/proof_of_address";

        $this->withToken($this->mobileToken($this->buyer))
            ->get('/api/seller-verification/documents/proof_of_address')
            ->assertOk();
        $this->withToken($this->mobileToken($this->otherBuyer))
            ->get('/api/seller-verification/documents/proof_of_address')
            ->assertNotFound();
        $this->withToken($this->adminToken())->get("/api{$url}")->assertOk();
        $this->withToken($this->mobileToken($this->buyer))->get("/api{$url}")->assertForbidden();
    }

    // -------------------------------------------------------------------
    // Farm photos
    // -------------------------------------------------------------------

    #[Test]
    public function an_application_can_be_submitted_without_farm_photos(): void
    {
        $this->stageBoth($this->buyer);

        $this->submit($this->buyer)
            ->assertCreated()
            ->assertJsonPath('data.has_proof_of_address', true)
            ->assertJsonPath('data.farm_photo_ids', []);
    }

    #[Test]
    public function several_farm_photos_are_kept_and_moved_onto_the_record(): void
    {
        $this->stageBoth($this->buyer);
        $first = $this->upload($this->buyer, DocType::FarmPhoto)
            ->assertCreated()
            ->json('data.photo_id');
        $second = $this->upload($this->buyer, DocType::FarmPhoto)
            ->assertCreated()
            ->json('data.photo_id');

        $this->assertNotSame($first, $second);

        $response = $this->submit($this->buyer)->assertCreated();

        $this->assertEqualsCanonicalizing(
            [$first, $second],
            $response->json('data.farm_photo_ids'),
        );

        $verification = SellerVerification::query()->firstOrFail();
        $disk = Storage::disk(SellerVerificationDocumentService::DISK);

        $this->assertCount(2, $verification->farm_photo_paths);
        foreach ($verification->farm_photo_paths as $path) {
            $this->assertStringStartsWith("verifications/{$verification->id}/", $path);
            $this->assertTrue($disk->exists($path));
        }
        $this->assertSame([], $disk->files(sprintf('staging/%d', $this->buyer->id)));
    }

    #[Test]
    public function farm_photos_are_limited_per_application(): void
    {
        for ($i = 0; $i < SellerVerificationDocumentService::MAX_FARM_PHOTOS; $i++) {
            $this->upload($this->buyer, DocType::FarmPhoto)->assertCreated();
        }

        $this->upload($this->buyer, DocType::FarmPhoto)
            ->assertUnprocessable()
            ->assertJsonValidationErrors('document');
    }

    #[Test]
    public function a_staged_farm_photo_can_be_removed_by_its_owner_only(): void
    {
        $id = $this->upload($this->buyer, DocType::FarmPhoto)->json('data.photo_id');
        $disk = Storage::disk(SellerVerificationDocumentService::DISK);
        $staging = sprintf('staging/%d', $this->buyer->id);

        $this->withToken($this->mobileToken($this->otherBuyer))
            ->delete("/api/seller-verification/documents/farm_photo/{$id}")
            ->assertNotFound();
        $this->assertCount(1, $disk->files($staging));

        $this->withToken($this->mobileToken($this->buyer))
            ->delete("/api/seller-verification/documents/farm_photo/{$id}")
            ->assertOk();
        $this->assertSame([], $disk->files($staging));

        $this->withToken($this->mobileToken($this->buyer))
            ->delete("/api/seller-verification/documents/farm_photo/{$id}")
            ->assertNotFound();
    }

    #[Test]
    public function submitted_farm_photos_are_private_and_read_by_owner_or_admin(): void
    {
        $this->stageBoth($this->buyer);
        $id = $this->upload($this->buyer, DocType::FarmPhoto)->json('data.photo_id');
        $this->submit($this->buyer)->assertCreated();
        $verification = SellerVerification::query()->firstOrFail();

        $owner = $this->withToken($this->mobileToken($this->buyer))
            ->get("/api/seller-verification/documents/farm_photo/{$id}");
        $owner->assertOk();
        $this->assertStringContainsString('no-store', $owner->headers->get('Cache-Control', ''));

        $this->withToken($this->mobileToken($this->otherBuyer))
            ->get("/api/seller-verification/documents/farm_photo/{$id}")
            ->assertNotFound();

        $adminUrl = "/api/admin/seller-verifications/{$verification->id}/documents/farm_photo/{$id}";
        $this->withToken($this->adminToken())->get($adminUrl)->assertOk();
        $this->withToken($this->mobileToken($this->buyer))->get($adminUrl)->assertForbidden();
    }

    #[Test]
    public function an_id_outside_the_record_cannot_read_a_file(): void
    {
        $verification = $this->createVerification($this->buyer);
        $this->putDocument($verification, DocType::IdDocument);

        foreach (['unknown', '..%2F..%2F.env', 'id_document'] as $id) {
            $this->withToken($this->adminToken())
                ->get("/api/admin/seller-verifications/{$verification->id}/documents/farm_photo/{$id}")
                ->assertNotFound();
        }
    }

    #[Test]
    public function no_response_carries_the_new_storage_paths(): void
    {
        $this->stageBoth($this->buyer);
        $this->upload($this->buyer, DocType::FarmPhoto)->assertCreated();
        $body = json_encode(
            $this->submit($this->buyer)->assertCreated()->json(),
            JSON_THROW_ON_ERROR,
        );

        $this->assertStringNotContainsString('verifications/', $body);
        $this->assertStringNotContainsString('proof_of_address_path', $body);
        $this->assertStringNotContainsString('farm_photo_paths', $body);
    }

    // -------------------------------------------------------------------
    // Optional business name
    // -------------------------------------------------------------------

    #[Test]
    public function an_application_without_a_business_name_can_be_reviewed(): void
    {
        $this->stageBoth($this->buyer);
        $this->submit($this->buyer)
            ->assertCreated()
            ->assertJsonPath('data.business_name', null);

        $verification = SellerVerification::query()->firstOrFail();

        $this->withToken($this->adminToken())
            ->postJson("/api/admin/seller-verifications/{$verification->id}/approve")
            ->assertOk()
            ->assertJsonPath('data.business_name', null);
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
