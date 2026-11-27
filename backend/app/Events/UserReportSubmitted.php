<?php

namespace App\Events;

use Illuminate\Broadcasting\PrivateChannel;

/**
 * A user filed a report against another account.
 *
 * Submitting a report is not an audited administrative action, so it writes
 * no activity and therefore produces no `ActivityRecorded` broadcast. This
 * dedicated event lets the Admin Web refresh its pending-report queue live
 * without changing what the audit log records.
 *
 * The payload is the report id only. The reporter, the reported account, the
 * description and any evidence stay behind the admin API, which re-checks
 * authorization when the Admin Web re-fetches.
 */
class UserReportSubmitted extends BroadcastEvent
{
    public function __construct(public readonly int $reportId) {}

    public function broadcastOn(): array
    {
        return [new PrivateChannel('admin')];
    }

    public function broadcastAs(): string
    {
        return 'user-report.submitted';
    }

    public function broadcastWith(): array
    {
        return ['report_id' => $this->reportId];
    }
}
