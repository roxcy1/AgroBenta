<?php

namespace Tests\Feature\Admin;

use App\Enums\ListingStatus;
use App\Enums\SellerCapability;
use App\Enums\SellerVerificationStatus;
use App\Enums\TransactionStatus;
use App\Enums\UserRole;
use App\Models\Activity;
use App\Models\Listing;
use App\Models\SellerVerification;
use App\Models\Transaction;
use App\Models\User;
use App\Repositories\Admin\AdminReportRepository;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

class ReportExportTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    private User $buyer;

    private User $seller;

    protected function setUp(): void
    {
        parent::setUp();

        $this->admin = User::factory()->create([
            'role' => UserRole::Admin,
            'seller_capability' => SellerCapability::Buyer,
            'created_at' => now()->subDays(30),
        ]);

        $this->buyer = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $this->seller = User::factory()->seller()->create([
            'role' => UserRole::User,
        ]);
    }

    private function adminToken(): string
    {
        return $this->admin->createToken('admin_token', ['admin'])->plainTextToken;
    }

    /**
     * @param  array<string, string>  $query
     */
    private function exportCsv(string $dataset, array $query = []): TestResponse
    {
        $url = '/api/admin/reports/export/'.$dataset;

        if ($query !== []) {
            $url .= '?'.http_build_query($query);
        }

        return $this->withHeader('Authorization', "Bearer {$this->adminToken()}")
            ->get($url);
    }

    /**
     * Read a streamed CSV response back into rows.
     *
     * @return list<list<string|null>>
     */
    private function rows(TestResponse $response): array
    {
        $handle = fopen('php://temp', 'r+');
        fwrite($handle, $response->streamedContent());
        rewind($handle);

        $rows = [];

        while (($row = fgetcsv($handle, 0, ',', '"', '')) !== false) {
            $rows[] = $row;
        }

        fclose($handle);

        return $rows;
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function createListing(array $overrides = []): Listing
    {
        return Listing::forceCreate(array_merge([
            'seller_id' => $this->seller->id,
            'livestock_type' => 'cattle',
            'breed' => 'Angus',
            'age_value' => 2,
            'age_unit' => 'year',
            'gender' => 'male',
            'weight_value' => 500,
            'weight_unit' => 'kg',
            'quantity' => 1,
            'asking_price' => 50000.00,
            'location' => 'Trinidad, Bohol',
            'health_status' => 'healthy',
            'vaccination' => 'up_to_date',
            'short_description' => 'Healthy Angus bull',
            'photos' => [],
            'status' => ListingStatus::Active,
        ], $overrides));
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function createTransaction(Listing $listing, array $overrides = []): Transaction
    {
        return Transaction::forceCreate(array_merge([
            'buyer_id' => $this->buyer->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'quantity' => 1,
            'total_amount' => 50000.00,
            'status' => TransactionStatus::Completed,
        ], $overrides));
    }

    public function test_guest_cannot_export_report_data(): void
    {
        $this->get('/api/admin/reports/export/transactions')->assertStatus(401);
    }

    public function test_regular_user_cannot_export_report_data(): void
    {
        $token = $this->buyer->createToken('user_token')->plainTextToken;

        $this->withHeader('Authorization', "Bearer {$token}")
            ->get('/api/admin/reports/export/transactions')
            ->assertStatus(403);
    }

    public function test_admin_receives_a_csv_download_named_after_the_dataset(): void
    {
        $response = $this->exportCsv('transactions', ['date_from' => '2026-01-01']);

        $response->assertStatus(200);
        $response->assertHeader('content-type', 'text/csv; charset=UTF-8');
        $response->assertDownload();

        $disposition = $response->baseResponse->headers->get('content-disposition');

        $this->assertIsString($disposition);
        $this->assertStringContainsString('agrobenta-reports-transactions-from-2026-01-01-', $disposition);
    }

    public function test_transactions_export_has_one_row_per_transaction_in_the_range(): void
    {
        $listing = $this->createListing(['created_at' => now()->subDays(10)]);

        $older = $this->createTransaction($listing, ['created_at' => now()->subDays(2)]);
        $newer = $this->createTransaction($listing, [
            'total_amount' => 32500.00,
            'status' => TransactionStatus::Pending,
            'created_at' => now()->subDay(),
        ]);
        $outside = $this->createTransaction($listing, ['created_at' => now()->subDays(10)]);

        $rows = $this->rows($this->exportCsv('transactions', [
            'date_from' => now()->subDays(3)->format('Y-m-d'),
        ]));

        $this->assertSame([
            'Transaction ID',
            'Created At',
            'Status',
            'Fulfillment Status',
            'Buyer ID',
            'Buyer Name',
            'Buyer Email',
            'Seller ID',
            'Seller Name',
            'Seller Email',
            'Listing ID',
            'Livestock Type',
            'Breed',
            'Quantity',
            'Total Amount',
            'Pickup Date',
            'Payment Method',
            'Collection Method',
            'Completed At',
        ], $rows[0]);

        $this->assertCount(3, $rows);
        $this->assertSame((string) $newer->id, $rows[1][0]);
        $this->assertSame('pending', $rows[1][2]);
        $this->assertSame('32500.00', $rows[1][14]);
        $this->assertSame((string) $older->id, $rows[2][0]);
        $this->assertNotContains((string) $outside->id, array_column(array_slice($rows, 1), 0));
    }

    public function test_listings_export_contains_the_listing_record(): void
    {
        $listing = $this->createListing(['created_at' => now()->subDay()]);

        $rows = $this->rows($this->exportCsv('listings'));

        $this->assertSame('Listing ID', $rows[0][0]);
        $this->assertCount(2, $rows);

        $row = $rows[1];

        $this->assertSame((string) $listing->id, $row[0]);
        $this->assertSame('active', $row[2]);
        $this->assertSame((string) $this->seller->id, $row[3]);
        $this->assertSame($this->seller->name, $row[4]);
        $this->assertSame('cattle', $row[6]);
        $this->assertSame('Angus', $row[7]);
        $this->assertSame('50000.00', $row[14]);
        $this->assertSame('Trinidad, Bohol', $row[15]);
    }

    public function test_users_export_contains_only_accounts_registered_in_the_range(): void
    {
        $rows = $this->rows($this->exportCsv('users', [
            'date_from' => now()->subDays(2)->format('Y-m-d'),
        ]));

        $this->assertSame([
            'User ID',
            'Registered At',
            'Name',
            'Email',
            'Role',
            'Seller Capability',
            'Email Verified At',
        ], $rows[0]);

        $ids = array_column(array_slice($rows, 1), 0);

        $this->assertContains((string) $this->buyer->id, $ids);
        $this->assertContains((string) $this->seller->id, $ids);
        $this->assertNotContains((string) $this->admin->id, $ids);
        $this->assertNotContains('Password', $rows[0]);
        $this->assertNotContains('remember_token', $rows[0]);
    }

    public function test_seller_verifications_export_keeps_every_submission(): void
    {
        foreach ([SellerVerificationStatus::Approved, SellerVerificationStatus::Rejected] as $status) {
            SellerVerification::forceCreate([
                'user_id' => $this->seller->id,
                'business_name' => 'Test Livestock Farm',
                'business_location' => 'Trinidad, Bohol',
                'status' => $status,
                'submitted_at' => now()->subDay(),
                'reviewed_at' => now(),
                'reviewed_by' => $this->admin->id,
                'created_at' => now()->subDay(),
            ]);
        }

        $rows = $this->rows($this->exportCsv('seller-verifications'));

        $this->assertSame('Verification ID', $rows[0][0]);
        $this->assertCount(3, $rows);
        $this->assertSame((string) $this->seller->id, $rows[1][4]);
        $this->assertSame($this->seller->name, $rows[1][5]);
        $this->assertSame('Test Livestock Farm', $rows[1][7]);
        $this->assertSame($this->admin->name, $rows[1][11]);

        $statuses = array_column(array_slice($rows, 1), 3);
        sort($statuses);

        $this->assertSame(['approved', 'rejected'], $statuses);
    }

    public function test_activities_export_includes_system_activity_without_an_actor(): void
    {
        Activity::factory()
            ->createdAt(now()->subDay())
            ->create([
                'user_id' => $this->admin->id,
                'action' => 'settings_updated',
                'description' => 'Updated platform settings',
            ]);

        Activity::factory()
            ->createdAt(now()->subHours(2))
            ->create([
                'user_id' => null,
                'action' => 'system_check',
                'description' => 'Scheduled maintenance check',
            ]);

        $rows = $this->rows($this->exportCsv('activities'));

        $this->assertSame('Activity ID', $rows[0][0]);
        $this->assertCount(3, $rows);

        $this->assertSame('system_check', $rows[1][5]);
        $this->assertSame('', $rows[1][2]);
        $this->assertSame('', $rows[1][3]);

        $this->assertSame('settings_updated', $rows[2][5]);
        $this->assertSame((string) $this->admin->id, $rows[2][2]);
    }

    public function test_empty_range_writes_only_the_header(): void
    {
        $rows = $this->rows($this->exportCsv('transactions', [
            'date_from' => now()->subDays(10)->format('Y-m-d'),
            'date_to' => now()->subDays(5)->format('Y-m-d'),
        ]));

        $this->assertCount(1, $rows);
        $this->assertSame('Transaction ID', $rows[0][0]);
    }

    public function test_spreadsheet_formula_values_are_neutralised(): void
    {
        User::factory()->create([
            'name' => '=HYPERLINK("http://example.test","click")',
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $rows = $this->rows($this->exportCsv('users'));

        $names = array_column(array_slice($rows, 1), 2);

        $this->assertContains('\'=HYPERLINK("http://example.test","click")', $names);
    }

    public function test_invalid_date_range_is_rejected(): void
    {
        $this->exportCsv('users', [
            'date_from' => '2026-12-31',
            'date_to' => '2026-01-01',
        ])->assertStatus(422);
    }

    public function test_unknown_dataset_is_not_found(): void
    {
        $this->exportCsv('inquiries')->assertStatus(404);
    }

    public function test_transactions_export_names_soft_deleted_buyer_and_seller(): void
    {
        $listing = $this->createListing();
        $this->createTransaction($listing);

        $this->buyer->delete();
        $this->seller->delete();

        $rows = $this->rows($this->exportCsv('transactions'));

        $this->assertCount(2, $rows);

        $row = $rows[1];

        $this->assertSame((string) $this->buyer->id, $row[4]);
        $this->assertSame($this->buyer->name, $row[5]);
        $this->assertSame($this->buyer->email, $row[6]);
        $this->assertSame((string) $this->seller->id, $row[7]);
        $this->assertSame($this->seller->name, $row[8]);
        $this->assertSame($this->seller->email, $row[9]);
    }

    public function test_listings_export_names_a_soft_deleted_seller(): void
    {
        $listing = $this->createListing();

        $this->seller->delete();

        $rows = $this->rows($this->exportCsv('listings'));

        $this->assertCount(2, $rows);

        $row = $rows[1];

        $this->assertSame((string) $listing->id, $row[0]);
        $this->assertSame((string) $this->seller->id, $row[3]);
        $this->assertSame($this->seller->name, $row[4]);
        $this->assertSame($this->seller->email, $row[5]);
    }

    public function test_seller_verifications_export_names_soft_deleted_applicant_and_reviewer(): void
    {
        $reviewer = User::factory()->create([
            'role' => UserRole::Admin,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        SellerVerification::forceCreate([
            'user_id' => $this->seller->id,
            'business_name' => 'Test Livestock Farm',
            'business_location' => 'Trinidad, Bohol',
            'status' => SellerVerificationStatus::Approved,
            'submitted_at' => now()->subDay(),
            'reviewed_at' => now(),
            'reviewed_by' => $reviewer->id,
            'created_at' => now()->subDay(),
        ]);

        $this->seller->delete();
        $reviewer->delete();

        $rows = $this->rows($this->exportCsv('seller-verifications'));

        $this->assertCount(2, $rows);

        $row = $rows[1];

        $this->assertSame((string) $this->seller->id, $row[4]);
        $this->assertSame($this->seller->name, $row[5]);
        $this->assertSame($this->seller->email, $row[6]);
        $this->assertSame('Test Livestock Farm', $row[7]);
        $this->assertSame($reviewer->name, $row[11]);
    }

    public function test_activities_export_names_a_soft_deleted_actor(): void
    {
        $actor = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        Activity::factory()->create([
            'user_id' => $actor->id,
            'action' => 'settings_updated',
            'description' => 'Updated platform settings',
            'created_at' => now()->subDay(),
        ]);

        $actor->delete();

        $rows = $this->rows($this->exportCsv('activities'));

        $this->assertCount(2, $rows);

        $row = $rows[1];

        $this->assertSame((string) $actor->id, $row[2]);
        $this->assertSame($actor->name, $row[3]);
        $this->assertSame($actor->email, $row[4]);
    }

    public function test_users_export_excludes_deactivated_accounts(): void
    {
        $this->buyer->delete();

        $rows = $this->rows($this->exportCsv('users'));

        $ids = array_column(array_slice($rows, 1), 0);

        $this->assertContains((string) $this->seller->id, $ids);
        $this->assertNotContains((string) $this->buyer->id, $ids);
    }

    public function test_transaction_export_eager_loads_related_accounts_once_per_chunk(): void
    {
        $listing = $this->createListing();
        $this->createTransaction($listing);

        $reports = app(AdminReportRepository::class);

        DB::enableQueryLog();
        DB::flushQueryLog();

        $singleRowExport = $this->exportTransactionRows($reports);
        $oneRowQueries = count(DB::getQueryLog());

        foreach (range(1, 4) as $index) {
            $this->createTransaction($listing, ['created_at' => now()->subMinutes($index)]);
        }

        DB::flushQueryLog();

        $fiveRowExport = $this->exportTransactionRows($reports);
        $fiveRowQueries = count(DB::getQueryLog());

        DB::disableQueryLog();

        $this->assertSame(1, $singleRowExport);
        $this->assertSame(5, $fiveRowExport);
        $this->assertSame($oneRowQueries, $fiveRowQueries);
        $this->assertLessThanOrEqual(6, $oneRowQueries);
    }

    /**
     * Read the transaction export the way the CSV writer does — including the
     * related accounts it writes — and return how many rows were read.
     */
    private function exportTransactionRows(AdminReportRepository $reports): int
    {
        $count = 0;

        foreach ($reports->exportTransactions() as $transaction) {
            $count++;

            $this->assertNotNull($transaction->buyer);
            $this->assertNotNull($transaction->seller);
            $this->assertNotNull($transaction->listing);
        }

        return $count;
    }
}
