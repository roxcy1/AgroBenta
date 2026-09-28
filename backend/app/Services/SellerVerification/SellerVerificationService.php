<?php

namespace App\Services\SellerVerification;

use App\Enums\SellerVerificationStatus;
use App\Models\SellerVerification;
use App\Models\User;
use App\Repositories\SellerVerification\SellerVerificationRepository;
use DomainException;
use Illuminate\Support\Facades\DB;

/**
 * Application logic for mobile seller verification.
 *
 * This is where the resubmission rule becomes behaviour. The rule
 * (functional documentation §3.2) is load-bearing and easy to implement wrongly:
 * a rejected verification is resubmitted by **creating a new record**, never by
 * updating the rejected one back to `submitted`, and the previous record is
 * history that must survive.
 *
 * That is why there is no update path in this class at all. A method that
 * "resubmits" by mutating a row would satisfy a test that only checks the status
 * and quietly destroy the history the documentation requires, so the only way to
 * reach a second record is a second insert.
 */
class SellerVerificationService
{
    /**
     * `@throws DomainException` with this code when a verification is already
     * open. The controller maps it to the contract's `409`.
     */
    public const string OPEN_EXISTS = 'seller_verification.open_exists';

    public function __construct(
        private readonly SellerVerificationRepository $verifications,
    ) {
        //
    }

    /**
     * Submit a verification for the authenticated user.
     *
     * Returns the new record. The caller maps the refusal to `409`; an approved
     * seller is refused earlier, by the request class, with `403` — that is a
     * different situation (nothing to submit) from a duplicate.
     *
     * @param  array{business_name: string, business_location?: string|null, business_description?: string|null, id_document_ref?: string|null}  $input
     *
     * @throws DomainException when the user already has an open verification.
     */
    public function submit(User $user, array $input): SellerVerification
    {
        return DB::transaction(function () use ($user, $input): SellerVerification {
            // The user's own row is locked, not the verification rows. There is
            // nothing to lock when no verification exists yet, so locking the
            // verifications would serialise nothing and two rapid submissions
            // would both see "no open record" and both insert. Locking the user
            // gives every submission by this account the same mutex, which is the
            // row that exists in both the racing and the non-racing case.
            $locked = User::query()
                ->lockForUpdate()
                ->findOrFail($user->id);

            if ($this->verifications->openFor($locked) !== null) {
                throw new DomainException(self::OPEN_EXISTS);
            }

            // Every field except the four client-supplied ones is written here.
            // `status` and `submitted_at` are server-set, and
            // `seller_capability` is not touched at all: submitting grants
            // nothing, and only an administrator approval can promote a buyer
            // (functional documentation §2.6).
            return SellerVerification::create([
                'user_id' => $locked->id,
                'business_name' => $input['business_name'],
                'business_location' => $input['business_location'] ?? null,
                'business_description' => $input['business_description'] ?? null,
                'id_document_ref' => $input['id_document_ref'] ?? null,
                'status' => SellerVerificationStatus::Submitted,
                'admin_note' => null,
                'reviewed_by' => null,
                'reviewed_at' => null,
                'submitted_at' => now(),
            ]);
        });
    }

    /**
     * The user's current verification state, or null if they never submitted.
     *
     * Exactly one record, never a list: history is preserved server-side, and a
     * client rendering "your verification status" must not have to pick the
     * newest of N (contract §5.3).
     */
    public function currentFor(User $user): ?SellerVerification
    {
        return $this->verifications->latestFor($user);
    }
}
