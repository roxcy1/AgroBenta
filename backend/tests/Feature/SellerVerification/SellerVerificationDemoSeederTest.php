<?php

namespace Tests\Feature\SellerVerification;

use App\Enums\SellerCapability;
use App\Enums\SellerVerificationStatus as Status;
use App\Enums\UserRole;
use App\Models\SellerVerification;
use App\Models\User;
use Database\Seeders\DatabaseSeeder;
use Database\Seeders\SellerVerificationDemoSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class SellerVerificationDemoSeederTest extends TestCase
{
    use RefreshDatabase;

    private const DEMO_DOMAIN = 'agrobenta.test';

    private const REVIEWER_EMAIL = 'verify.reviewer@agrobenta.test';

    /**
     * Expected latest-record count per status. Sums to 15 applicants, which is
     * the number of distinct demo applicant accounts.
     *
     * @var array<string, int>
     */
    private const EXPECTED_LATEST_COUNTS = [
        'submitted' => 5,
        'pending_review' => 3,
        'approved' => 4,
        'rejected' => 3,
    ];

    private function seedDemo(): void
    {
        $this->seed(SellerVerificationDemoSeeder::class);
    }

    /**
     * @return \Illuminate\Database\Eloquent\Collection<int, User>
     */
    private function demoApplicants()
    {
        return User::query()
            ->where('role', UserRole::User->value)
            ->where('email', 'like', '%@'.self::DEMO_DOMAIN)
            ->get();
    }

    private function applicant(string $localPart): User
    {
        return User::query()
            ->where('email', $localPart.'@'.self::DEMO_DOMAIN)
            ->firstOrFail();
    }

    private function latestRecordFor(User $applicant): SellerVerification
    {
        return SellerVerification::query()
            ->where('user_id', $applicant->id)
            ->orderByDesc('submitted_at')
            ->orderByDesc('id')
            ->firstOrFail();
    }

    private function adminToken(): string
    {
        return User::query()
            ->where('email', self::REVIEWER_EMAIL)
            ->firstOrFail()
            ->createToken('admin_token', ['admin'])
            ->plainTextToken;
    }

    public function test_it_creates_the_expected_demo_fixture(): void
    {
        $this->seedDemo();

        $this->assertSame(15, $this->demoApplicants()->count());
        $this->assertSame(1, User::query()->where('email', self::REVIEWER_EMAIL)->count());
        $this->assertSame(17, SellerVerification::query()->count());
    }

    public function test_each_status_latest_count_matches_the_seeded_data(): void
    {
        $this->seedDemo();

        $token = $this->adminToken();

        foreach (self::EXPECTED_LATEST_COUNTS as $status => $expected) {
            $this->withHeader('Authorization', "Bearer {$token}")
                ->getJson("/api/admin/seller-verifications?status={$status}&per_page=1")
                ->assertStatus(200)
                ->assertJsonPath('data.pagination.total', $expected);
        }
    }

    public function test_the_list_api_returns_only_the_latest_record_per_applicant(): void
    {
        $this->seedDemo();

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson('/api/admin/seller-verifications?per_page=100');

        $response->assertStatus(200);
        $response->assertJsonPath('data.pagination.total', 15);

        $sellerIds = collect($response->json('data.verifications'))->pluck('seller.id');

        $this->assertCount(15, $sellerIds);
        $this->assertCount(15, $sellerIds->unique(), 'The list must show one row per applicant.');
    }

    public function test_capability_matches_each_applicants_latest_record(): void
    {
        $this->seedDemo();

        foreach ($this->demoApplicants() as $applicant) {
            $latest = $this->latestRecordFor($applicant);

            $expected = $latest->status === Status::Approved
                ? SellerCapability::Seller
                : SellerCapability::Buyer;

            $this->assertSame(
                $expected,
                $applicant->seller_capability,
                "Applicant {$applicant->email} has the wrong capability for a {$latest->status->value} record.",
            );
        }
    }

    public function test_decided_records_carry_a_reviewer_and_rejections_carry_a_note(): void
    {
        $this->seedDemo();

        $decided = SellerVerification::query()
            ->whereIn('status', [Status::Approved->value, Status::Rejected->value])
            ->get();

        $this->assertNotEmpty($decided);

        foreach ($decided as $record) {
            $this->assertNotNull($record->reviewed_by);
            $this->assertNotNull($record->reviewed_at);
            $this->assertNotNull($record->reviewer);
        }

        foreach (SellerVerification::query()->where('status', Status::Rejected->value)->get() as $record) {
            $this->assertNotNull($record->admin_note);
            $this->assertNotSame('', trim((string) $record->admin_note));
        }

        foreach (SellerVerification::query()
            ->whereIn('status', [Status::Submitted->value, Status::PendingReview->value])
            ->get() as $record) {
            $this->assertNull($record->reviewed_by);
            $this->assertNull($record->reviewed_at);
        }
    }

    public function test_history_is_preserved_and_exposed_through_the_detail_api(): void
    {
        $this->seedDemo();

        $applicant = $this->applicant('verify.nathan.reyes');
        $latest = $this->latestRecordFor($applicant);

        $this->assertSame(Status::Submitted, $latest->status);

        $response = $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson("/api/admin/seller-verifications/{$latest->id}");

        $response->assertStatus(200);
        $response->assertJsonCount(1, 'history');
        $response->assertJsonPath('history.0.status', Status::Rejected->value);

        // The approved resubmission keeps its own rejected history too.
        $approvedApplicant = $this->applicant('verify.olivia.cruz');
        $approvedLatest = $this->latestRecordFor($approvedApplicant);

        $this->assertSame(Status::Approved, $approvedLatest->status);

        $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->getJson("/api/admin/seller-verifications/{$approvedLatest->id}")
            ->assertStatus(200)
            ->assertJsonCount(1, 'history')
            ->assertJsonPath('history.0.status', Status::Rejected->value);
    }

    public function test_nullable_fields_are_mixed(): void
    {
        $this->seedDemo();

        $this->assertSame(1, SellerVerification::query()
            ->whereNull('business_location')
            ->whereNull('business_description')
            ->whereNull('id_document_ref')
            ->count());
    }

    public function test_running_the_seeder_repeatedly_is_idempotent(): void
    {
        $this->seedDemo();

        $usersAfterFirst = User::query()->where('email', 'like', '%@'.self::DEMO_DOMAIN)->count();
        $recordsAfterFirst = SellerVerification::query()->count();

        $this->seedDemo();
        $this->seedDemo();

        $this->assertSame($usersAfterFirst, User::query()->where('email', 'like', '%@'.self::DEMO_DOMAIN)->count());
        $this->assertSame($recordsAfterFirst, SellerVerification::query()->count());
        $this->assertSame(16, $usersAfterFirst);
        $this->assertSame(17, $recordsAfterFirst);
    }

    public function test_it_does_not_modify_unrelated_records(): void
    {
        $realUser = User::factory()->create([
            'email' => 'real.user@example.com',
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $realVerification = SellerVerification::create([
            'user_id' => $realUser->id,
            'business_name' => 'Real Farm',
            'status' => Status::Submitted,
            'submitted_at' => now(),
        ]);

        $this->seedDemo();
        $this->seedDemo();

        $this->assertSame(1, SellerVerification::query()->where('user_id', $realUser->id)->count());
        $this->assertSame('Real Farm', $realVerification->fresh()->business_name);
        $this->assertSame(Status::Submitted, $realVerification->fresh()->status);
        $this->assertSame(SellerCapability::Buyer, $realUser->fresh()->seller_capability);
    }

    public function test_the_default_database_seeder_does_not_create_demo_data(): void
    {
        $this->seed(DatabaseSeeder::class);

        $this->assertSame(0, SellerVerification::query()->count());
        $this->assertSame(
            0,
            User::query()->where('email', 'like', 'verify.%@'.self::DEMO_DOMAIN)->count(),
        );
    }
}
