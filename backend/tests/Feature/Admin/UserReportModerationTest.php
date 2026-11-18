<?php

namespace Tests\Feature\Admin;

use App\Enums\ListingStatus;
use App\Enums\SellerCapability;
use App\Enums\TransactionStatus;
use App\Enums\UserReportReason;
use App\Enums\UserReportStatus;
use App\Enums\UserRole;
use App\Models\Activity;
use App\Models\Listing;
use App\Models\Transaction;
use App\Models\User;
use App\Models\UserReport;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class UserReportModerationTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();

        Storage::fake('user-report-evidence');

        $this->admin = User::factory()->create([
            'role' => UserRole::Admin,
            'seller_capability' => SellerCapability::Buyer,
        ]);
    }

    private function adminToken(): string
    {
        return $this->admin->createToken('admin_token', ['admin'])->plainTextToken;
    }

    private function createReport(
        User $reporter,
        User $target,
        UserReportStatus $status = UserReportStatus::Pending,
        ?string $evidencePath = null,
    ): UserReport {
        return UserReport::create([
            'reporter_id' => $reporter->id,
            'reported_user_id' => $target->id,
            'reason' => UserReportReason::ScamFraud,
            'description' => 'Asked for payment outside the platform.',
            'evidence_path' => $evidencePath,
            'status' => $status,
        ]);
    }

    public function test_admin_can_list_and_filter_reports_with_pagination_and_total(): void
    {
        $reporterOne = User::factory()->create(['name' => 'Reporter One']);
        $reporterTwo = User::factory()->create(['name' => 'Reporter Two']);
        $target = User::factory()->create(['name' => 'Reported User']);

        $pending = $this->createReport($reporterOne, $target);
        $dismissed = $this->createReport($reporterTwo, $target, UserReportStatus::Dismissed);

        $response = $this->withHeader('Authorization', 'Bearer '.$this->adminToken())
            ->getJson('/api/admin/user-reports');

        $response->assertOk()
            ->assertJsonPath('data.pagination.total', 2)
            ->assertJsonPath('data.reports.0.reporter.name', 'Reporter Two')
            ->assertJsonPath('data.reports.0.reported_user.name', 'Reported User')
            ->assertJsonPath('data.reports.0.reason_label', 'Scam/Fraud')
            ->assertJsonPath('data.reports.0.status_label', 'Dismissed')
            ->assertJsonPath('data.reports.0.has_evidence', false)
            ->assertJsonMissingPath('data.reports.0.evidence_path');

        $this->withHeader('Authorization', 'Bearer '.$this->adminToken())
            ->getJson('/api/admin/user-reports?status=pending')
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 1)
            ->assertJsonPath('data.reports.0.id', $pending->id);

        $this->assertSame(UserReportStatus::Dismissed, $dismissed->fresh()->status);
    }

    public function test_admin_can_show_one_report_with_full_details(): void
    {
        $reporter = User::factory()->create();
        $target = User::factory()->create();
        $report = $this->createReport($reporter, $target);

        $this->withHeader('Authorization', 'Bearer '.$this->adminToken())
            ->getJson("/api/admin/user-reports/{$report->id}")
            ->assertOk()
            ->assertJsonPath('data.id', $report->id)
            ->assertJsonPath('data.description', 'Asked for payment outside the platform.')
            ->assertJsonPath('data.reporter.id', $reporter->id)
            ->assertJsonPath('data.reported_user.id', $target->id);
    }

    public function test_report_detail_exposes_the_pending_transaction_warning_count(): void
    {
        $reporter = User::factory()->create();
        $target = User::factory()->seller()->create();
        $listing = Listing::create([
            'seller_id' => $target->id,
            'livestock_type' => 'cattle',
            'breed' => 'Angus',
            'quantity' => 1,
            'total_quantity' => 1,
            'asking_price' => 1000,
            'location' => 'Purok 1, Barangay Poblacion, Trinidad, Bohol',
            'short_description' => 'Report warning listing.',
            'photos' => [],
            'status' => ListingStatus::Active,
        ]);
        $buyer = User::factory()->create();
        Transaction::create([
            'buyer_id' => $buyer->id,
            'seller_id' => $target->id,
            'listing_id' => $listing->id,
            'quantity' => 1,
            'total_amount' => 1000,
            'status' => TransactionStatus::Pending,
        ]);
        $report = $this->createReport($reporter, $target);

        $this->withHeader('Authorization', 'Bearer '.$this->adminToken())
            ->getJson("/api/admin/user-reports/{$report->id}")
            ->assertOk()
            ->assertJsonPath('data.reported_user.pending_transactions_count', 1);
    }

    public function test_evidence_is_streamed_privately_and_absent_evidence_is_404(): void
    {
        $reporter = User::factory()->create();
        $target = User::factory()->create();
        $path = 'reports/evidence.jpg';
        Storage::disk('user-report-evidence')->put($path, 'image-bytes');
        $report = $this->createReport($reporter, $target, evidencePath: $path);
        $noEvidence = $this->createReport($reporter, $target);

        $response = $this->withHeader('Authorization', 'Bearer '.$this->adminToken())
            ->get("/api/admin/user-reports/{$report->id}/evidence");

        $response->assertOk();
        $this->assertSame('image-bytes', $response->streamedContent());
        $this->assertStringContainsString('private', (string) $response->headers->get('Cache-Control'));
        $this->assertStringContainsString('no-store', (string) $response->headers->get('Cache-Control'));

        $this->withHeader('Authorization', 'Bearer '.$this->adminToken())
            ->getJson("/api/admin/user-reports/{$noEvidence->id}/evidence")
            ->assertNotFound();
    }

    public function test_dismissal_requires_pending_status_and_never_deactivates_the_target(): void
    {
        $reporter = User::factory()->create();
        $target = User::factory()->create();
        $report = $this->createReport($reporter, $target);
        $token = $this->adminToken();

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson("/api/admin/user-reports/{$report->id}/dismiss", [
                'admin_note' => 'Evidence was inconclusive.',
            ])
            ->assertOk()
            ->assertJsonPath('data.status', 'dismissed')
            ->assertJsonPath('data.admin_note', 'Evidence was inconclusive.')
            ->assertJsonPath('data.reviewer.id', $this->admin->id);

        $this->assertDatabaseHas('users', ['id' => $target->id, 'deleted_at' => null]);
        $this->assertDatabaseHas('user_reports', [
            'id' => $report->id,
            'status' => UserReportStatus::Dismissed->value,
            'reviewed_by' => $this->admin->id,
        ]);
        $this->assertDatabaseHas('activities', [
            'user_id' => $this->admin->id,
            'action' => 'user_report_dismissed',
        ]);

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson("/api/admin/user-reports/{$report->id}/dismiss", [])
            ->assertStatus(409);
    }

    public function test_report_deactivation_requires_a_reason_and_marks_the_report_actioned_atomically(): void
    {
        $reporter = User::factory()->create();
        $target = User::factory()->create();
        $report = $this->createReport($reporter, $target);
        $token = $this->adminToken();

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson("/api/admin/user-reports/{$report->id}/deactivate", [])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('reason');

        $this->assertDatabaseHas('users', ['id' => $target->id, 'deleted_at' => null]);
        $this->assertDatabaseHas('user_reports', [
            'id' => $report->id,
            'status' => UserReportStatus::Pending->value,
        ]);

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson("/api/admin/user-reports/{$report->id}/deactivate", [
                'reason' => 'Scam confirmed from the evidence.',
            ])
            ->assertOk()
            ->assertJsonPath('data.status', 'actioned')
            ->assertJsonPath('data.admin_note', 'Scam confirmed from the evidence.')
            ->assertJsonPath('data.reported_user.status', 'deactivated');

        $this->assertSoftDeleted('users', ['id' => $target->id]);
        $this->assertDatabaseHas('users', [
            'id' => $target->id,
            'deactivation_reason' => 'Scam confirmed from the evidence.',
            'deactivated_by' => $this->admin->id,
        ]);
        $this->assertDatabaseHas('user_reports', [
            'id' => $report->id,
            'status' => UserReportStatus::Actioned->value,
            'reviewed_by' => $this->admin->id,
        ]);
        $this->assertDatabaseHas('activities', [
            'user_id' => $this->admin->id,
            'action' => 'user_report_actioned',
        ]);

        $activity = Activity::query()
            ->where('user_id', $this->admin->id)
            ->where('action', 'user_report_actioned')
            ->latest('id')
            ->firstOrFail();
        $this->assertSame(
            'Scam confirmed from the evidence.',
            $activity->metadata['context']['administrative_reason'],
        );
    }

    public function test_deactivation_of_an_admin_target_is_refused_and_leaves_the_report_pending(): void
    {
        $reporter = User::factory()->create();
        $targetAdmin = User::factory()->admin()->create();
        $report = $this->createReport($reporter, $targetAdmin);

        $this->withHeader('Authorization', 'Bearer '.$this->adminToken())
            ->postJson("/api/admin/user-reports/{$report->id}/deactivate", [
                'reason' => 'Attempted moderation of an administrator.',
            ])
            ->assertUnprocessable();

        $this->assertDatabaseHas('users', ['id' => $targetAdmin->id, 'deleted_at' => null]);
        $this->assertDatabaseHas('user_reports', [
            'id' => $report->id,
            'status' => UserReportStatus::Pending->value,
        ]);
    }

    public function test_already_deactivated_target_is_refused_and_leaves_the_report_pending(): void
    {
        $reporter = User::factory()->create();
        $target = User::factory()->create();
        $report = $this->createReport($reporter, $target);
        $target->delete();

        $this->withHeader('Authorization', 'Bearer '.$this->adminToken())
            ->postJson("/api/admin/user-reports/{$report->id}/deactivate", [
                'reason' => 'Already handled elsewhere.',
            ])
            ->assertStatus(409);

        $this->assertDatabaseHas('user_reports', [
            'id' => $report->id,
            'status' => UserReportStatus::Pending->value,
        ]);
    }

    public function test_mobile_tokens_and_guests_cannot_moderate_reports(): void
    {
        $reporter = User::factory()->create();
        $target = User::factory()->create();
        $report = $this->createReport($reporter, $target);

        $this->getJson('/api/admin/user-reports')->assertUnauthorized();

        $mobile = User::factory()->create();
        $token = $mobile->createToken('mobile', ['mobile'])->plainTextToken;

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->getJson('/api/admin/user-reports')
            ->assertForbidden();

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson("/api/admin/user-reports/{$report->id}/dismiss", [])
            ->assertForbidden();
    }
}
