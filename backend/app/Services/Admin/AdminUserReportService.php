<?php

namespace App\Services\Admin;

use App\Enums\ActivityAction;
use App\Models\User;
use App\Models\UserReport;
use App\Repositories\Admin\AdminUserReportRepository;
use App\Services\ActivityLogger;
use App\Services\UserReport\UserReportEvidenceService;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\StreamedResponse;

class AdminUserReportService
{
    public function __construct(
        private readonly AdminUserReportRepository $reports,
        private readonly AdminUserService $users,
        private readonly ActivityLogger $activity,
        private readonly UserReportEvidenceService $evidence,
    ) {
        //
    }

    public function listReports(?string $status = null, int $perPage = 15): LengthAwarePaginator
    {
        return $this->reports->list($status, $perPage);
    }

    public function findReport(int $id): UserReport
    {
        $report = $this->reports->find($id);

        abort_if($report === null, 404, 'Report not found.');

        return $report;
    }

    public function evidenceResponse(UserReport $report): StreamedResponse
    {
        return $this->evidence->response($report);
    }

    /**
     * Dismiss one pending report. The target account is not changed.
     */
    public function dismiss(UserReport $report, User $actor, ?string $note): UserReport
    {
        $note = $note === null ? null : trim($note);

        return DB::transaction(function () use ($report, $actor, $note): UserReport {
            $locked = $this->reports->lock((int) $report->getKey());

            abort_if($locked === null, 404, 'Report not found.');
            abort_unless(
                $locked->isPending(),
                409,
                'This report has already been reviewed.',
            );

            $dismissed = $this->reports->markDismissed(
                $locked,
                (int) $actor->getKey(),
                $note === '' ? null : $note,
            );

            $this->activity->log(
                $actor,
                ActivityAction::UserReportDismissed,
                sprintf('User report #%d dismissed.', $dismissed->getKey()),
                [
                    'target_type' => 'user_report',
                    'target_id' => $dismissed->getKey(),
                    'context' => [
                        'reported_user_id' => $dismissed->reported_user_id,
                        'reason' => $dismissed->reason?->value,
                        'admin_note' => $dismissed->admin_note,
                    ],
                    'changes' => [
                        'status' => ['from' => 'pending', 'to' => 'dismissed'],
                    ],
                ],
            );

            return $this->findReport((int) $dismissed->getKey());
        });
    }

    /**
     * Deactivate the reported account and mark the report actioned.
     *
     * The account write reuses AdminUserService, so self/last-administrator
     * protection and the existing audit path are preserved. Both writes share
     * one database transaction: a failed deactivation leaves the report
     * pending.
     */
    public function deactivate(UserReport $report, User $actor, string $reason): UserReport
    {
        $reason = trim($reason);
        abort_if($reason === '', 422, 'An administrative reason is required.');

        return DB::transaction(function () use ($report, $actor, $reason): UserReport {
            $locked = $this->reports->lock((int) $report->getKey());

            abort_if($locked === null, 404, 'Report not found.');
            abort_unless(
                $locked->isPending(),
                409,
                'This report has already been reviewed.',
            );

            $target = $locked->reportedUser;

            abort_if($target === null, 404, 'Reported user not found.');
            abort_if(
                $target->trashed(),
                409,
                'This account is already deactivated.',
            );
            abort_if(
                $target->isAdmin(),
                422,
                'Administrator accounts cannot be deactivated from a report.',
            );

            $this->users->deleteUser($target, $actor, $reason);

            $actioned = $this->reports->markActioned(
                $locked,
                (int) $actor->getKey(),
                $reason,
            );

            $this->activity->log(
                $actor,
                ActivityAction::UserReportActioned,
                sprintf('User report #%d actioned.', $actioned->getKey()),
                [
                    'target_type' => 'user_report',
                    'target_id' => $actioned->getKey(),
                    'context' => [
                        'reported_user_id' => $actioned->reported_user_id,
                        'reason' => $actioned->reason?->value,
                        'administrative_reason' => $reason,
                    ],
                    'changes' => [
                        'status' => ['from' => 'pending', 'to' => 'actioned'],
                    ],
                ],
            );

            return $this->findReport((int) $actioned->getKey());
        });
    }
}
