<?php

namespace Database\Seeders;

use App\Enums\SellerCapability;
use App\Enums\SellerVerificationStatus;
use App\Enums\UserRole;
use App\Models\SellerVerification;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Seeder;
use Illuminate\Support\Str;

/**
 * Seeds realistic, development-only seller-verification data for the admin
 * review UI.
 *
 * The seeder is idempotent. Demo accounts are matched by their reserved
 * `@agrobenta.test` addresses (all namespaced with `verify.` so they can never
 * collide with the transaction demo users), and each verification record is
 * matched by its `(user_id, business_name)` pair — so running it repeatedly
 * never creates duplicates and never modifies a record it did not create
 * itself.
 *
 * It is intentionally not registered in DatabaseSeeder so a blanket `db:seed`
 * can never write demo data to a production database. Run it explicitly:
 *
 *     php artisan db:seed --class=SellerVerificationDemoSeeder
 *
 * The data covers every scenario the review UI can show:
 *
 *   - `submitted` and `pending_review` records — the open states.
 *   - `approved` records whose applicant holds seller capability.
 *   - `rejected` records with a meaningful admin note and buyer capability.
 *   - Two applicants with history: a rejected record followed by a newer
 *     resubmission (one resubmitted and still open, one resubmitted and
 *     approved). Only the latest record per applicant appears in the list; the
 *     earlier ones are visible through the detail API's history.
 *
 * Optional fields are deliberately mixed so the nullable `business_location`,
 * `business_description` and `id_document_ref` columns are all exercised.
 * `id_document_ref` stays a plain-text reference — no document is uploaded or
 * stored.
 */
class SellerVerificationDemoSeeder extends Seeder
{
    /**
     * Reserved domain for demo accounts.
     */
    private const DEMO_DOMAIN = 'agrobenta.test';

    /**
     * The administrator recorded as the reviewer of every decided record.
     */
    private const REVIEWER_NAME = 'Demo Reviewer';

    private const REVIEWER_EMAIL = 'verify.reviewer';

    /**
     * Demo applicants and their verification records, grouped per applicant.
     *
     * `submitted_days_ago` and `reviewed_after_days` are relative to the run so
     * the data always looks recent. They are *not* what makes the seeder
     * idempotent — the `(user_id, business_name)` pair is.
     *
     * @var list<array{
     *     name: string,
     *     email: string,
     *     capability: SellerCapability,
     *     records: list<array<string, mixed>>
     * }>
     */
    private const APPLICANTS = [
        // --- Submitted: newly arrived, not yet picked up. ---
        [
            'name' => 'Ana Reyes',
            'email' => 'verify.ana.reyes',
            'capability' => SellerCapability::Buyer,
            'records' => [[
                'business_name' => 'Riverside Poultry — New Submission',
                'status' => SellerVerificationStatus::Submitted,
                'submitted_days_ago' => 2,
                'location' => 'Davao del Sur',
                'description' => 'Free-range native chickens raised along the Davao river.',
                'id_document_ref' => 'DEMO-REF-1001',
            ]],
        ],
        [
            'name' => 'Ben Torres',
            'email' => 'verify.ben.torres',
            'capability' => SellerCapability::Buyer,
            'records' => [[
                'business_name' => 'Vigan Heritage Cattle — New Submission',
                'status' => SellerVerificationStatus::Submitted,
                'submitted_days_ago' => 1,
                'description' => 'Heritage cattle raised in Ilocos Sur.',
            ]],
        ],
        [
            'name' => 'Carla Domingo',
            'email' => 'verify.carla.domingo',
            'capability' => SellerCapability::Buyer,
            'records' => [[
                'business_name' => 'Bohol Highland Goat — New Submission',
                'status' => SellerVerificationStatus::Submitted,
                'submitted_days_ago' => 4,
                'location' => 'Bohol',
                'id_document_ref' => 'DEMO-REF-1003',
            ]],
        ],
        [
            'name' => 'Diego Santos',
            'email' => 'verify.diego.santos',
            'capability' => SellerCapability::Buyer,
            'records' => [[
                // Every optional field left empty on purpose.
                'business_name' => 'Baguio Dairy Farm — New Submission',
                'status' => SellerVerificationStatus::Submitted,
                'submitted_days_ago' => 6,
            ]],
        ],

        // --- Pending review: under active review. ---
        [
            'name' => 'Elena Bautista',
            'email' => 'verify.elena.bautista',
            'capability' => SellerCapability::Buyer,
            'records' => [[
                'business_name' => 'Cebu Lechon Swine — In Review',
                'status' => SellerVerificationStatus::PendingReview,
                'submitted_days_ago' => 8,
                'location' => 'Cebu',
                'description' => 'Backyard swine raised for the lechon trade.',
                'id_document_ref' => 'DEMO-REF-1005',
            ]],
        ],
        [
            'name' => 'Franco Delgado',
            'email' => 'verify.franco.delgado',
            'capability' => SellerCapability::Buyer,
            'records' => [[
                'business_name' => 'Iloilo Native Chicken — In Review',
                'status' => SellerVerificationStatus::PendingReview,
                'submitted_days_ago' => 9,
                'location' => 'Iloilo',
            ]],
        ],
        [
            'name' => 'Gina Roxas',
            'email' => 'verify.gina.roxas',
            'capability' => SellerCapability::Buyer,
            'records' => [[
                'business_name' => 'Cagayan Carabao — In Review',
                'status' => SellerVerificationStatus::PendingReview,
                'submitted_days_ago' => 10,
                'description' => 'Carabao for farm work and dairy production.',
                'id_document_ref' => 'DEMO-REF-1007',
            ]],
        ],

        // --- Approved: seller capability granted. ---
        [
            'name' => 'Henry Aquino',
            'email' => 'verify.henry.aquino',
            'capability' => SellerCapability::Seller,
            'records' => [[
                'business_name' => 'Pampanga Duck Farm — Approved',
                'status' => SellerVerificationStatus::Approved,
                'submitted_days_ago' => 15,
                'reviewed_after_days' => 2,
                'location' => 'Pampanga',
                'description' => 'Peking ducks supplied to local restaurants.',
                'id_document_ref' => 'DEMO-REF-1008',
                'admin_note' => 'Documents verified. Approved for selling.',
            ]],
        ],
        [
            'name' => 'Isabel Navarro',
            'email' => 'verify.isabel.navarro',
            'capability' => SellerCapability::Seller,
            'records' => [[
                'business_name' => 'Batangas Beef Cattle — Approved',
                'status' => SellerVerificationStatus::Approved,
                'submitted_days_ago' => 18,
                'reviewed_after_days' => 3,
                'location' => 'Batangas',
                // Approved with no note, to show the nullable decision note.
            ]],
        ],
        [
            'name' => 'Jonas Lim',
            'email' => 'verify.jonas.lim',
            'capability' => SellerCapability::Seller,
            'records' => [[
                'business_name' => 'Pangasinan Goat Ranch — Approved',
                'status' => SellerVerificationStatus::Approved,
                'submitted_days_ago' => 21,
                'reviewed_after_days' => 1,
                'location' => 'Pangasinan',
                'description' => 'Boer goats raised for meat.',
                'id_document_ref' => 'DEMO-REF-1010',
                'admin_note' => 'Verified on site. Approved for selling.',
            ]],
        ],

        // --- Rejected: capability revoked, note explains why. ---
        [
            'name' => 'Karen Villamor',
            'email' => 'verify.karen.villamor',
            'capability' => SellerCapability::Buyer,
            'records' => [[
                'business_name' => 'Quezon Backyard Swine — Rejected',
                'status' => SellerVerificationStatus::Rejected,
                'submitted_days_ago' => 12,
                'reviewed_after_days' => 2,
                'location' => 'Quezon',
                'description' => 'Small backyard swine operation.',
                'id_document_ref' => 'DEMO-REF-1011',
                'admin_note' => 'ID reference could not be verified. Please resubmit with a valid reference.',
            ]],
        ],
        [
            'name' => 'Leo Marquez',
            'email' => 'verify.leo.marquez',
            'capability' => SellerCapability::Buyer,
            'records' => [[
                'business_name' => 'Nueva Ecija Poultry — Rejected',
                'status' => SellerVerificationStatus::Rejected,
                'submitted_days_ago' => 14,
                'reviewed_after_days' => 1,
                'location' => 'Nueva Ecija',
                'admin_note' => 'Business location could not be confirmed. Resubmission required.',
            ]],
        ],
        [
            'name' => 'Maria Aguilar',
            'email' => 'verify.maria.aguilar',
            'capability' => SellerCapability::Buyer,
            'records' => [[
                'business_name' => 'Tarlac Sheep Farm — Rejected',
                'status' => SellerVerificationStatus::Rejected,
                'submitted_days_ago' => 16,
                'reviewed_after_days' => 4,
                'description' => 'Sheep raised for wool and meat.',
                'id_document_ref' => 'DEMO-REF-1013',
                'admin_note' => 'Insufficient business details provided. Please add a description.',
            ]],
        ],

        // --- History A: rejected, then resubmitted and still open. ---
        [
            'name' => 'Nathan Reyes',
            'email' => 'verify.nathan.reyes',
            'capability' => SellerCapability::Buyer,
            'records' => [
                [
                    'business_name' => 'Old Mill Dairy — Prior Rejection',
                    'status' => SellerVerificationStatus::Rejected,
                    'submitted_days_ago' => 25,
                    'reviewed_after_days' => 3,
                    'location' => 'Laguna',
                    'description' => 'Dairy cattle raised in Laguna.',
                    'id_document_ref' => 'DEMO-REF-1014A',
                    'admin_note' => 'Incomplete documents. Resubmit with a valid ID reference.',
                ],
                [
                    'business_name' => 'Old Mill Dairy — Resubmitted',
                    'status' => SellerVerificationStatus::Submitted,
                    'submitted_days_ago' => 3,
                    'location' => 'Laguna',
                    'description' => 'Dairy cattle raised in Laguna. Resubmitted with a corrected ID reference.',
                    'id_document_ref' => 'DEMO-REF-1014B',
                ],
            ],
        ],

        // --- History B: rejected, then resubmitted and approved. ---
        [
            'name' => 'Olivia Cruz',
            'email' => 'verify.olivia.cruz',
            'capability' => SellerCapability::Seller,
            'records' => [
                [
                    'business_name' => 'Cordillera Cattle — Prior Rejection',
                    'status' => SellerVerificationStatus::Rejected,
                    'submitted_days_ago' => 30,
                    'reviewed_after_days' => 2,
                    'location' => 'Benguet',
                    'description' => 'Highland cattle raised in Benguet.',
                    'admin_note' => 'Business location could not be verified at the time. Resubmission permitted.',
                ],
                [
                    'business_name' => 'Cordillera Cattle — Approved',
                    'status' => SellerVerificationStatus::Approved,
                    'submitted_days_ago' => 20,
                    'reviewed_after_days' => 1,
                    'location' => 'Benguet',
                    'description' => 'Highland cattle raised in Benguet. Resubmission verified.',
                    'id_document_ref' => 'DEMO-REF-1015B',
                    'admin_note' => 'Resubmission verified on site. Approved for selling.',
                ],
            ],
        ],
    ];

    public function run(): void
    {
        $reviewer = $this->ensureUser(
            self::REVIEWER_EMAIL.'@'.self::DEMO_DOMAIN,
            self::REVIEWER_NAME,
            UserRole::Admin,
            SellerCapability::Buyer,
        );

        $created = 0;

        foreach (self::APPLICANTS as $applicant) {
            $user = $this->ensureUser(
                $applicant['email'].'@'.self::DEMO_DOMAIN,
                $applicant['name'],
                UserRole::User,
                $applicant['capability'],
            );

            foreach ($applicant['records'] as $record) {
                if ($this->seedRecord($user, $reviewer, $record)) {
                    $created++;
                }
            }
        }

        $applicants = count(self::APPLICANTS);
        $total = $this->demoRecords()->count();

        $this->command?->info(
            "SellerVerificationDemoSeeder: {$applicants} demo applicant(s); {$created} new verification record(s) created; {$total} demo record(s) present.",
        );
    }

    /**
     * Reuses a demo account when it already exists, otherwise creates it.
     *
     * The authority columns are not mass assignable, so this trusted
     * server-side path sets them explicitly. Only the reserved demo domain is
     * ever touched. The password is random: these are demo accounts, not
     * logins.
     */
    private function ensureUser(string $email, string $name, UserRole $role, SellerCapability $capability): User
    {
        $user = User::query()->where('email', $email)->first() ?? new User;

        $user->forceFill([
            'name' => $name,
            'email' => $email,
            'role' => $role,
            'seller_capability' => $capability,
            'email_verified_at' => $user->email_verified_at ?? now(),
        ]);

        if (! $user->exists) {
            $user->forceFill(['password' => Str::random(40)]);
        }

        $user->save();

        return $user;
    }

    /**
     * Creates one verification record if it does not already exist.
     *
     * @param  array<string, mixed>  $record
     * @return bool whether a new record was created
     */
    private function seedRecord(User $applicant, User $reviewer, array $record): bool
    {
        $status = $record['status'];
        $decided = ! $status->isOpen();

        $submittedAt = now()
            ->subDays($record['submitted_days_ago'])
            ->setTime(9, 0, 0);

        $reviewedAt = $decided
            ? $submittedAt->copy()->addDays($record['reviewed_after_days'] ?? 1)
            : null;

        $verification = SellerVerification::firstOrCreate(
            [
                'user_id' => $applicant->id,
                'business_name' => $record['business_name'],
            ],
            [
                'business_location' => $record['location'] ?? null,
                'business_description' => $record['description'] ?? null,
                'id_document_ref' => $record['id_document_ref'] ?? null,
                'status' => $status,
                'admin_note' => $record['admin_note'] ?? null,
                'reviewed_by' => $decided ? $reviewer->id : null,
                'reviewed_at' => $reviewedAt,
                'submitted_at' => $submittedAt,
            ],
        );

        if (! $verification->wasRecentlyCreated) {
            return false;
        }

        // Align the audit timestamps with the business dates so the record reads
        // coherently. Mass assignment does not cover created_at/updated_at.
        $verification->forceFill([
            'created_at' => $submittedAt,
            'updated_at' => ($reviewedAt ?? $submittedAt)->copy(),
        ])->save();

        return true;
    }

    /**
     * Every verification record belonging to a demo account.
     *
     * @return Builder<SellerVerification>
     */
    private function demoRecords(): Builder
    {
        return SellerVerification::query()->whereHas('seller', function (Builder $query): void {
            $query->where('email', 'like', '%@'.self::DEMO_DOMAIN);
        });
    }
}
