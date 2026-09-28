<?php

namespace App\Repositories\SellerVerification;

use App\Models\SellerVerification;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;

/**
 * Data access for the mobile seller verification surface.
 *
 * Deliberately separate from `AdminSellerVerificationRepository`, for the same
 * reason the marketplace has its own: the admin repository lists *every*
 * verification across *every* user, ordered by `created_at desc` with no
 * dedupe, which is the correct shape for a review queue and the wrong one for
 * "your current verification status". Sharing it would invite the mobile
 * endpoint to return a queue instead of a record.
 *
 * The ordering rule lives here and is used by both reads and the submission
 * precondition, because the resubmission decision depends on exactly which
 * record counts as "most recent" and that must not be stated twice.
 */
class SellerVerificationRepository
{
    /**
     * The user's most recent verification, or null if they have never submitted.
     *
     * "Most recent" is `submitted_at desc, id desc` per contract §5.3. The
     * secondary sort is not decoration: `submitted_at` is a timestamp column and
     * two submissions in the same second would otherwise tie, leaving which
     * record counts as current up to the database's whim. `id desc` makes the
     * answer deterministic, and because ids are monotonic it always agrees with
     * the later submission.
     *
     * Ordering by `submitted_at` rather than `created_at` matters because
     * `submitted_at` is what the client sees and what a resubmission resets; the
     * admin repository's `created_at` ordering is not a substitute.
     */
    public function latestFor(User $user): ?SellerVerification
    {
        return $this->queryFor($user)
            ->orderByDesc('submitted_at')
            ->orderByDesc('id')
            ->first();
    }

    /**
     * The user's open verification, if one exists.
     *
     * `submitted` and `pending_review` both mean a review is in flight
     * (functional documentation §3.1), so either blocks a new submission
     * (contract §5.3, `409`). Resolved by ordering rather than by two queries so
     * that a user holding a rejected record *and* an open one — reachable by
     * resubmitting, then having the newest rejected while an older is somehow
     * still open — is judged on the record that actually governs them.
     */
    public function openFor(User $user): ?SellerVerification
    {
        return $this->queryFor($user)
            ->whereIn('status', ['submitted', 'pending_review'])
            ->orderByDesc('submitted_at')
            ->orderByDesc('id')
            ->first();
    }

    /**
     * Count of the user's verifications. Used by tests to prove a resubmission
     * creates a row rather than mutating the rejected one.
     */
    public function countFor(User $user): int
    {
        return $this->queryFor($user)->count();
    }

    /**
     * The base query: one user's own verifications, with no relations loaded.
     *
     * The mobile resource needs no relations — it deliberately omits both
     * `seller` and `reviewer` — so eager loading them here would be a query the
     * response never uses.
     */
    private function queryFor(User $user): Builder
    {
        return SellerVerification::query()->where('user_id', $user->id);
    }
}
