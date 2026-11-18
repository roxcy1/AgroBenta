<?php

namespace Tests\Feature\Report;

use App\Enums\SellerCapability;
use App\Enums\UserReportReason;
use App\Enums\UserReportStatus;
use App\Enums\UserRole;
use App\Models\User;
use App\Models\UserReport;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

class UserReportTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        Storage::fake('user-report-evidence');
    }

    private function mobileToken(User $user): string
    {
        return $user->createToken('mobile', ['mobile'])->plainTextToken;
    }

    private function reportPayload(User $target, array $overrides = []): array
    {
        return array_merge([
            'reported_user_id' => $target->id,
            'reason' => UserReportReason::Harassment->value,
            'description' => 'Threatening messages after an inquiry.',
        ], $overrides);
    }

    public static function rolePairs(): array
    {
        return [
            'buyer reports seller' => [SellerCapability::Buyer, SellerCapability::Seller],
            'buyer reports buyer' => [SellerCapability::Buyer, SellerCapability::Buyer],
            'seller reports buyer' => [SellerCapability::Seller, SellerCapability::Buyer],
            'seller reports seller' => [SellerCapability::Seller, SellerCapability::Seller],
        ];
    }

    #[DataProvider('rolePairs')]
    public function test_any_mobile_role_pair_can_file_a_report(
        SellerCapability $reporterCapability,
        SellerCapability $targetCapability,
    ): void {
        $reporter = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => $reporterCapability,
        ]);
        $target = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => $targetCapability,
        ]);

        $response = $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($reporter))
            ->postJson('/api/reports', $this->reportPayload($target));

        $response->assertCreated()
            ->assertJsonPath('success', true)
            ->assertJsonPath('message', 'Report submitted.')
            ->assertJsonPath('data.reason', UserReportReason::Harassment->value)
            ->assertJsonPath('data.status', UserReportStatus::Pending->value)
            ->assertJsonMissingPath('data.reporter_id')
            ->assertJsonMissingPath('data.reported_user_id')
            ->assertJsonMissingPath('data.evidence_path');

        $this->assertDatabaseHas('user_reports', [
            'reporter_id' => $reporter->id,
            'reported_user_id' => $target->id,
            'reason' => UserReportReason::Harassment->value,
            'status' => UserReportStatus::Pending->value,
        ]);
        $this->assertDatabaseHas('users', ['id' => $target->id, 'deleted_at' => null]);
    }

    public function test_self_report_is_rejected(): void
    {
        $user = User::factory()->create();

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($user))
            ->postJson('/api/reports', $this->reportPayload($user))
            ->assertUnprocessable();
    }

    public function test_administrator_target_is_rejected(): void
    {
        $reporter = User::factory()->create();
        $admin = User::factory()->admin()->create();

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($reporter))
            ->postJson('/api/reports', $this->reportPayload($admin))
            ->assertUnprocessable();

        $this->assertDatabaseCount('user_reports', 0);
    }

    public function test_deactivated_target_is_rejected(): void
    {
        $reporter = User::factory()->create();
        $target = User::factory()->create();
        $target->delete();

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($reporter))
            ->postJson('/api/reports', $this->reportPayload($target))
            ->assertUnprocessable();

        $this->assertDatabaseCount('user_reports', 0);
    }

    public function test_one_pending_report_per_pair_and_a_new_report_after_resolution(): void
    {
        $reporter = User::factory()->create();
        $target = User::factory()->create();
        $token = $this->mobileToken($reporter);

        $first = $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson('/api/reports', $this->reportPayload($target))
            ->assertCreated();

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson('/api/reports', $this->reportPayload($target))
            ->assertStatus(409);

        UserReport::query()->whereKey($first->json('data.id'))->update([
            'status' => UserReportStatus::Dismissed->value,
        ]);

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson('/api/reports', $this->reportPayload($target))
            ->assertCreated();
    }

    public function test_evidence_is_stored_privately_and_never_returned(): void
    {
        $reporter = User::factory()->create();
        $target = User::factory()->create();
        $token = $this->mobileToken($reporter);
        $file = UploadedFile::fake()->create('evidence.jpg', 10, 'image/jpeg');

        $response = $this->withHeader('Authorization', 'Bearer '.$token)
            ->post('/api/reports', $this->reportPayload($target, [
                'evidence' => $file,
            ]), ['Accept' => 'application/json']);

        $response->assertCreated()
            ->assertJsonMissingPath('data.evidence_path');

        $report = UserReport::query()->firstOrFail();

        $this->assertNotNull($report->evidence_path);
        $this->assertStringStartsWith('reports/', $report->evidence_path);
        $this->assertStringNotContainsString('http', $report->evidence_path);
        Storage::disk('user-report-evidence')->assertExists($report->evidence_path);
    }

    public function test_invalid_evidence_type_and_missing_fields_are_rejected(): void
    {
        $reporter = User::factory()->create();
        $target = User::factory()->create();
        $token = $this->mobileToken($reporter);

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->post('/api/reports', [
                'reported_user_id' => $target->id,
                'reason' => 'not_a_reason',
                'description' => 'short',
                'evidence' => UploadedFile::fake()->create('evidence.pdf', 100, 'application/pdf'),
            ], ['Accept' => 'application/json'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['reason', 'description', 'evidence']);
    }

    public function test_guest_and_admin_tokens_cannot_submit_reports(): void
    {
        $target = User::factory()->create();

        $this->postJson('/api/reports', $this->reportPayload($target))
            ->assertUnauthorized();

        $admin = User::factory()->admin()->create();
        $token = $admin->createToken('admin', ['admin'])->plainTextToken;

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson('/api/reports', $this->reportPayload($target))
            ->assertForbidden();
    }

    public function test_report_submission_is_rate_limited_per_account(): void
    {
        $reporter = User::factory()->create();
        $token = $this->mobileToken($reporter);

        for ($i = 0; $i < 5; $i++) {
            $target = User::factory()->create();

            $this->withHeader('Authorization', 'Bearer '.$token)
                ->postJson('/api/reports', $this->reportPayload($target))
                ->assertCreated();
        }

        $sixthTarget = User::factory()->create();

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson('/api/reports', $this->reportPayload($sixthTarget))
            ->assertStatus(429);
    }

    public function test_reporting_does_not_revoke_the_target_session_or_touch_their_listing(): void
    {
        $reporter = User::factory()->create();
        $target = User::factory()->seller()->create();
        $targetToken = $this->mobileToken($target);

        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($reporter))
            ->postJson('/api/reports', $this->reportPayload($target))
            ->assertCreated();

        $this->withHeader('Authorization', 'Bearer '.$targetToken)
            ->getJson('/api/auth/me')
            ->assertOk();

        $this->assertDatabaseHas('users', [
            'id' => $target->id,
            'deleted_at' => null,
        ]);
    }
}
