<?php

namespace Tests\Feature\Realtime;

use App\Enums\UserReportReason;
use App\Events\ActivityRecorded;
use App\Events\UserReportSubmitted;
use App\Models\User;
use App\Models\UserReport;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Storage;
use Illuminate\Testing\TestResponse;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * A submitted user report reaches connected administrators live.
 *
 * Report submission is not an audited action, so it produces no
 * `ActivityRecorded`; the dedicated `UserReportSubmitted` event refreshes the
 * Admin Web's report queue without adding anything to the audit log.
 */
class UserReportBroadcastTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        Storage::fake('user-report-evidence');
    }

    private function report(User $reporter, User $target): TestResponse
    {
        return $this->withHeader(
            'Authorization',
            'Bearer '.$reporter->createToken('mobile', ['mobile'])->plainTextToken,
        )->postJson('/api/reports', [
            'reported_user_id' => $target->id,
            'reason' => UserReportReason::Harassment->value,
            'description' => 'Threatening messages after an inquiry.',
        ]);
    }

    #[Test]
    public function a_submitted_report_is_broadcast_to_the_admin_channel_by_id_only(): void
    {
        Event::fake([UserReportSubmitted::class, ActivityRecorded::class]);
        $reporter = User::factory()->create();
        $target = User::factory()->create();

        $this->report($reporter, $target)->assertCreated();

        $report = UserReport::query()->sole();
        Event::assertDispatchedTimes(UserReportSubmitted::class, 1);
        Event::assertDispatched(UserReportSubmitted::class, function (UserReportSubmitted $event) use ($report): bool {
            $channels = $event->broadcastOn();

            return count($channels) === 1
                && $channels[0]->name === 'private-admin'
                && $event->broadcastAs() === 'user-report.submitted'
                // No reporter identity, description or evidence on the socket.
                && $event->broadcastWith() === ['report_id' => $report->id];
        });
    }

    #[Test]
    public function submitting_a_report_still_writes_no_audit_entry(): void
    {
        Event::fake([UserReportSubmitted::class, ActivityRecorded::class]);

        $this->report(User::factory()->create(), User::factory()->create())
            ->assertCreated();

        Event::assertNotDispatched(ActivityRecorded::class);
        $this->assertDatabaseCount('activities', 0);
    }

    #[Test]
    public function a_rejected_or_duplicate_report_broadcasts_nothing_more(): void
    {
        Event::fake([UserReportSubmitted::class]);
        $reporter = User::factory()->create();
        $target = User::factory()->create();

        $this->report($reporter, $reporter)->assertUnprocessable();
        Event::assertNotDispatched(UserReportSubmitted::class);

        $this->report($reporter, $target)->assertCreated();
        $this->report($reporter, $target)->assertConflict();

        Event::assertDispatchedTimes(UserReportSubmitted::class, 1);
    }
}
