<?php

namespace App\Services\UserReport;

use App\Enums\UserReportStatus;
use App\Models\User;
use App\Models\UserReport;
use App\Repositories\UserReport\UserReportRepository;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Throwable;

class UserReportService
{
    public function __construct(
        private readonly UserReportRepository $reports,
        private readonly UserReportEvidenceService $evidence,
    ) {
        //
    }

    /**
     * Create one pending report for the authenticated reporter.
     *
     * The reported account is locked before the duplicate check, so two
     * concurrent submissions for the same pair cannot both pass. No account,
     * session, listing, transaction or reservation is modified here.
     *
     * @param  array{reported_user_id: int, reason: string, description: string}  $attributes
     */
    public function create(User $reporter, array $attributes, ?UploadedFile $evidence = null): UserReport
    {
        return DB::transaction(function () use ($reporter, $attributes, $evidence): UserReport {
            $target = $this->reports->lockReportedUser((int) $attributes['reported_user_id']);

            abort_if($target === null, 404, 'User not found.');

            if ($target->is($reporter)) {
                abort(422, 'You cannot report your own account.');
            }

            if ($target->isAdmin()) {
                abort(422, 'Administrator accounts cannot be reported.');
            }

            if ($target->trashed()) {
                abort(422, 'This account is no longer available.');
            }

            if ($this->reports->hasPendingBetween((int) $reporter->getKey(), (int) $target->getKey())) {
                abort(409, 'You already have a pending report about this user.');
            }

            $path = $evidence === null ? null : $this->evidence->store($evidence);

            try {
                return $this->reports->create([
                    'reporter_id' => (int) $reporter->getKey(),
                    'reported_user_id' => (int) $target->getKey(),
                    'reason' => $attributes['reason'],
                    'description' => $attributes['description'],
                    'evidence_path' => $path,
                    'status' => UserReportStatus::Pending->value,
                ]);
            } catch (Throwable $exception) {
                $this->evidence->delete($path);

                throw $exception;
            }
        });
    }
}
