<?php

namespace App\Services\Admin;

use App\Enums\ActivityAction;
use App\Enums\InquiryStatus;
use App\Models\Inquiry;
use App\Models\User;
use App\Repositories\Admin\AdminInquiryRepository;
use App\Services\ActivityLogger;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;

class AdminInquiryService
{
    public function __construct(
        private readonly AdminInquiryRepository $inquiries,
        private readonly ActivityLogger $activity,
    ) {
        //
    }

    public function listInquiries(
        ?string $search = null,
        ?string $status = null,
        int $perPage = 15,
    ): LengthAwarePaginator {
        return $this->inquiries->list($search, $status, $perPage);
    }

    /**
     * Move an inquiry along the administrator workflow.
     *
     * The transition is unconstrained by design: an administrator may reopen a
     * closed inquiry or re-mark a responded one, because the status is a
     * bookmark for staff, not a state machine the buyer depends on. The audit
     * entry records what it actually changed.
     */
    public function updateStatus(Inquiry $inquiry, User $actor, string $status): Inquiry
    {
        return DB::transaction(function () use ($inquiry, $actor, $status): Inquiry {
            $to = InquiryStatus::from($status);
            $previous = $inquiry->status->value;

            $inquiry->update(['status' => $to]);

            $this->activity->log(
                $actor,
                ActivityAction::InquiryStatusUpdated,
                sprintf('Inquiry #%d marked %s.', $inquiry->getKey(), $to->label()),
                [
                    'target_type' => 'inquiry',
                    'target_id' => $inquiry->getKey(),
                    'context' => [
                        'buyer_id' => $inquiry->buyer_id,
                        'seller_id' => $inquiry->seller_id,
                        'listing_id' => $inquiry->listing_id,
                    ],
                    'changes' => [
                        'status' => ['from' => $previous, 'to' => $to->value],
                    ],
                ],
            );

            return $inquiry->fresh(['buyer:id,name,email', 'seller:id,name,email', 'listing:id,livestock_type,breed']);
        });
    }

    /**
     * Remove an inquiry. The audit entry is written with the identifiers the
     * row carried, since the row itself is gone immediately after.
     */
    public function delete(Inquiry $inquiry, User $actor): void
    {
        DB::transaction(function () use ($inquiry, $actor): void {
            $metadata = [
                'target_type' => 'inquiry',
                'target_id' => $inquiry->getKey(),
                'context' => [
                    'buyer_id' => $inquiry->buyer_id,
                    'seller_id' => $inquiry->seller_id,
                    'listing_id' => $inquiry->listing_id,
                    'status' => $inquiry->status->value,
                ],
            ];

            $inquiry->delete();

            $this->activity->log(
                $actor,
                ActivityAction::InquiryDeleted,
                sprintf('Inquiry #%d deleted.', $metadata['target_id']),
                $metadata,
            );
        });
    }
}
