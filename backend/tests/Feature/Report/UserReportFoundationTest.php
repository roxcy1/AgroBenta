<?php

namespace Tests\Feature\Report;

use App\Enums\SellerCapability;
use App\Enums\UserReportReason;
use App\Enums\UserReportStatus;
use App\Enums\UserRole;
use App\Models\User;
use App\Models\UserReport;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

class UserReportFoundationTest extends TestCase
{
    use RefreshDatabase;

    public function test_user_reports_table_has_the_approved_columns(): void
    {
        $this->assertTrue(Schema::hasColumns('user_reports', [
            'id',
            'reporter_id',
            'reported_user_id',
            'reason',
            'description',
            'evidence_path',
            'status',
            'reviewed_by',
            'reviewed_at',
            'admin_note',
            'created_at',
            'updated_at',
        ]));
    }

    public function test_users_table_has_deactivation_metadata(): void
    {
        $this->assertTrue(Schema::hasColumns('users', [
            'deactivation_reason',
            'deactivated_by',
            'deleted_at',
        ]));
    }

    public function test_reason_and_status_enums_have_the_approved_values_and_labels(): void
    {
        $this->assertSame([
            'scam_fraud' => 'Scam/Fraud',
            'harassment' => 'Harassment',
            'misleading_information' => 'Misleading Information',
            'spam_suspicious_activity' => 'Spam/Suspicious Activity',
            'inappropriate_content' => 'Inappropriate Content',
            'other' => 'Other',
        ], collect(UserReportReason::cases())
            ->mapWithKeys(fn (UserReportReason $reason): array => [$reason->value => $reason->label()])
            ->all());

        $this->assertSame(['pending', 'dismissed', 'actioned'], array_map(
            fn (UserReportStatus $status): string => $status->value,
            UserReportStatus::cases(),
        ));
        $this->assertTrue(UserReportStatus::Pending->isPending());
        $this->assertFalse(UserReportStatus::Dismissed->isPending());
    }

    public function test_report_casts_and_relationships_resolve_soft_deleted_users(): void
    {
        $reporter = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);
        $reported = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Seller,
        ]);
        $reviewer = User::factory()->create([
            'role' => UserRole::Admin,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $report = UserReport::create([
            'reporter_id' => $reporter->id,
            'reported_user_id' => $reported->id,
            'reason' => UserReportReason::Harassment,
            'description' => 'Abusive messages after an inquiry.',
            'status' => UserReportStatus::Pending,
        ]);

        $this->assertInstanceOf(UserReportReason::class, $report->reason);
        $this->assertInstanceOf(UserReportStatus::class, $report->status);
        $this->assertTrue($report->isPending());

        $report->forceFill([
            'status' => UserReportStatus::Dismissed,
            'reviewed_by' => $reviewer->id,
            'reviewed_at' => now(),
            'admin_note' => 'No actionable evidence.',
        ])->save();

        $report->refresh();

        $this->assertSame(UserReportStatus::Dismissed, $report->status);
        $this->assertNotNull($report->reviewed_at);
        $this->assertSame($reviewer->id, $report->reviewer?->id);

        $reported->delete();

        $this->assertSame($reported->id, $report->fresh()->reportedUser?->id);
        $this->assertTrue($report->fresh()->reportedUser->trashed());
        $this->assertSame($reporter->id, $report->reporter?->id);
    }

    public function test_user_report_relations_are_exposed_on_both_sides(): void
    {
        $reporter = User::factory()->create();
        $reported = User::factory()->create();

        UserReport::create([
            'reporter_id' => $reporter->id,
            'reported_user_id' => $reported->id,
            'reason' => UserReportReason::SpamSuspiciousActivity,
            'description' => 'Repeated unsolicited messages.',
            'status' => UserReportStatus::Pending,
        ]);

        $this->assertSame(1, $reporter->sentReports()->count());
        $this->assertSame(1, $reported->receivedReports()->count());
    }

    public function test_evidence_disk_is_private_and_has_no_public_url(): void
    {
        $disk = config('filesystems.disks.user-report-evidence');

        $this->assertIsArray($disk);
        $this->assertSame('private', $disk['visibility'] ?? null);
        $this->assertArrayNotHasKey('url', $disk);
        $this->assertStringContainsString('user-report-evidence', (string) ($disk['root'] ?? ''));
    }
}
