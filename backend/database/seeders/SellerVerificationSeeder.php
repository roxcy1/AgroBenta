<?php

namespace Database\Seeders;

use App\Enums\SellerCapability;
use App\Enums\SellerVerificationStatus;
use App\Enums\UserRole;
use App\Models\SellerVerification;
use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;

/**
 * Seeds realistic, development-only seller verification data.
 *
 * The seeder is idempotent: demo seller accounts are matched by their reserved
 * `@agrobenta.test` addresses and verification records by their
 * (user_id, business_name) business key, so running it repeatedly never creates
 * duplicates and never modifies records it did not create itself.
 *
 * It is intentionally not registered in DatabaseSeeder so a blanket `db:seed`
 * can never write demo data to a production database. Run it explicitly:
 *
 *     php artisan db:seed --class=SellerVerificationSeeder
 */
class SellerVerificationSeeder extends Seeder
{
    /**
     * Reserved domain for demo accounts, keeping them easy to recognise and
     * impossible to collide with a real user's email address.
     */
    private const DEMO_DOMAIN = 'agrobenta.test';

    /**
     * Number of days after submission that a decided application was reviewed.
     */
    private const REVIEW_LEAD_DAYS = 3;

    /**
     * Demo sellers and their verification applications, as
     * [display name, email local part, business name, business location,
     *  status, days since submission, admin note].
     *
     * The statuses are spread across every value so the dashboard's
     * "Verifications by Outcome" chart (approved vs rejected) and the reports
     * status distribution are populated.
     *
     * @var list<array{0: string, 1: string, 2: string, 3: string, 4: string, 5: int, 6: string|null}>
     */
    private const SELLERS = [
        ['Liza Mercado', 'liza.mercado', 'Mercado Livestock', 'Bukidnon', 'approved', 25, 'Documents verified against the submitted business permit.'],
        ['Bacolod Livestock Trading', 'bacolod.livestock', 'Bacolod Livestock Trading', 'Negros Occidental', 'approved', 55, 'Accredited livestock trader with complete paperwork.'],
        ['North Ridge Ranch', 'northridge.ranch', 'North Ridge Ranch', 'Lanao del Norte', 'rejected', 80, 'Submitted ID could not be verified with the issuing office.'],
        ['San Isidro Poultry', 'sanisidro.poultry', 'San Isidro Poultry', 'Pampanga', 'rejected', 110, 'Business permit on file had expired at the time of review.'],
        ['Valencia Cattle Co.', 'valencia.cattle', 'Valencia Cattle Co.', 'Negros Oriental', 'pending_review', 15, null],
        ['Amadeo Goat Farm', 'amadeo.goat', 'Amadeo Goat Farm', 'Cavite', 'submitted', 5, null],
    ];

    public function run(): void
    {
        $reviewer = User::query()
            ->where('role', UserRole::Admin)
            ->orderBy('id')
            ->first();

        $created = 0;

        foreach (self::SELLERS as [$name, $localPart, $businessName, $location, $status, $daysAgo, $note]) {
            $seller = $this->ensureSeller($localPart.'@'.self::DEMO_DOMAIN, $name);
            $submittedAt = now()->subDays($daysAgo)->setTime(9, 0);

            if ($this->seedVerification(
                $seller,
                $businessName,
                $location,
                SellerVerificationStatus::from($status),
                $submittedAt,
                $note,
                $reviewer,
            )) {
                $created++;
            }
        }

        $total = SellerVerification::query()->count();

        $this->command?->info(
            "SellerVerificationSeeder: {$created} demo verification(s) created, {$total} total in the database.",
        );
    }

    /**
     * Reuses a demo seller account when it already exists, otherwise creates it.
     *
     * The authority columns are not mass assignable, so this trusted server-side
     * path sets them explicitly. The password is random: these accounts are demo
     * applicants, not logins.
     */
    private function ensureSeller(string $email, string $name): User
    {
        $user = User::query()->where('email', $email)->first();

        if ($user !== null) {
            return $user;
        }

        $user = new User;
        $user->forceFill([
            'name' => $name,
            'email' => $email,
            'password' => Str::random(40),
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Seller,
            'email_verified_at' => now(),
        ])->save();

        return $user;
    }

    /**
     * Creates one verification application for a seller, keyed by
     * (user_id, business_name) so re-runs are no-ops.
     */
    private function seedVerification(
        User $seller,
        string $businessName,
        string $location,
        SellerVerificationStatus $status,
        Carbon $submittedAt,
        ?string $note,
        ?User $reviewer,
    ): bool {
        $decided = in_array($status, [SellerVerificationStatus::Approved, SellerVerificationStatus::Rejected], true);

        $verification = SellerVerification::firstOrCreate(
            [
                'user_id' => $seller->id,
                'business_name' => $businessName,
            ],
            [
                'business_location' => $location,
                'business_description' => "{$businessName} is applying for verified seller status.",
                'id_document_ref' => 'DEMO-'.strtoupper(Str::slug($businessName)),
                'status' => $status,
                'admin_note' => $note,
                'reviewed_by' => $decided ? $reviewer?->id : null,
                'reviewed_at' => $decided ? $submittedAt->copy()->addDays(self::REVIEW_LEAD_DAYS) : null,
                'submitted_at' => $submittedAt,
            ],
        );

        if (! $verification->wasRecentlyCreated) {
            return false;
        }

        // The reports aggregate and date-filter the verification trend by
        // created_at, while the admin list orders by submitted_at; keep both
        // aligned so the demo records behave consistently.
        $verification->forceFill([
            'created_at' => $submittedAt,
            'updated_at' => $submittedAt,
        ])->save();

        return true;
    }
}
