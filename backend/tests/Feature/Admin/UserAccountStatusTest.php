<?php

namespace Tests\Feature\Admin;

use App\Enums\ListingStatus;
use App\Enums\SellerCapability;
use App\Enums\TransactionStatus;
use App\Enums\UserReportReason;
use App\Enums\UserReportStatus;
use App\Enums\UserRole;
use App\Models\Activity;
use App\Models\Listing;
use App\Models\Transaction;
use App\Models\User;
use App\Models\UserReport;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class UserAccountStatusTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();

        $this->admin = User::factory()->create([
            'role' => UserRole::Admin,
            'seller_capability' => SellerCapability::Buyer,
        ]);
    }

    private function adminToken(): string
    {
        return $this->admin->createToken('admin_token', ['admin'])->plainTextToken;
    }

    private function activeListing(User $seller): Listing
    {
        return Listing::create([
            'seller_id' => $seller->id,
            'livestock_type' => 'cattle',
            'breed' => 'Angus',
            'quantity' => 1,
            'total_quantity' => 1,
            'asking_price' => 1000,
            'location' => 'Purok 1, Barangay Poblacion, Trinidad, Bohol',
            'short_description' => 'Report lifecycle listing.',
            'photos' => [],
            'status' => ListingStatus::Active,
        ]);
    }

    public function test_deactivation_requires_a_reason(): void
    {
        $user = User::factory()->create();

        $this->withHeader('Authorization', 'Bearer '.$this->adminToken())
            ->deleteJson("/api/admin/users/{$user->id}", [])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('reason');

        $this->assertDatabaseHas('users', ['id' => $user->id, 'deleted_at' => null]);
    }

    public function test_deactivation_persists_reason_actor_and_audit_history(): void
    {
        $user = User::factory()->create();

        $response = $this->withHeader('Authorization', 'Bearer '.$this->adminToken())
            ->deleteJson("/api/admin/users/{$user->id}", [
                'reason' => 'Confirmed fraudulent listing activity.',
            ]);

        $response->assertOk()
            ->assertJsonPath('data.status', 'deactivated')
            ->assertJsonPath('data.deactivation_reason', 'Confirmed fraudulent listing activity.')
            ->assertJsonPath('data.deactivated_by.id', $this->admin->id);

        $this->assertSoftDeleted('users', ['id' => $user->id]);
        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'deactivation_reason' => 'Confirmed fraudulent listing activity.',
            'deactivated_by' => $this->admin->id,
        ]);

        $activity = Activity::query()
            ->where('user_id', $this->admin->id)
            ->where('action', 'admin_user_deleted')
            ->latest('id')
            ->firstOrFail();

        $this->assertSame(
            'Confirmed fraudulent listing activity.',
            $activity->metadata['context']['reason'],
        );
    }

    public function test_default_list_is_active_only_and_status_filter_reaches_deactivated_accounts(): void
    {
        $active = User::factory()->create(['name' => 'Active Account']);
        $deactivated = User::factory()->create(['name' => 'Deactivated Account']);
        $deactivated->delete();

        $token = $this->adminToken();

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->getJson('/api/admin/users?search=Account')
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 1)
            ->assertJsonPath('data.users.0.id', $active->id);

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->getJson('/api/admin/users?search=Account&status=deactivated')
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 1)
            ->assertJsonPath('data.users.0.id', $deactivated->id)
            ->assertJsonPath('data.users.0.status', 'deactivated');

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->getJson('/api/admin/users?search=Account&status=all')
            ->assertOk()
            ->assertJsonPath('data.pagination.total', 2);

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->getJson("/api/admin/users/{$deactivated->id}")
            ->assertOk()
            ->assertJsonPath('data.status', 'deactivated');
    }

    public function test_admin_list_exposes_report_count_and_pending_transaction_warning(): void
    {
        $reporterOne = User::factory()->create();
        $reporterTwo = User::factory()->create();
        $target = User::factory()->seller()->create();

        UserReport::create([
            'reporter_id' => $reporterOne->id,
            'reported_user_id' => $target->id,
            'reason' => UserReportReason::Harassment,
            'description' => 'First report.',
            'status' => UserReportStatus::Pending,
        ]);
        UserReport::create([
            'reporter_id' => $reporterTwo->id,
            'reported_user_id' => $target->id,
            'reason' => UserReportReason::ScamFraud,
            'description' => 'Second report.',
            'status' => UserReportStatus::Dismissed,
        ]);

        $listing = $this->activeListing($target);
        $buyer = User::factory()->create();

        Transaction::create([
            'buyer_id' => $buyer->id,
            'seller_id' => $target->id,
            'listing_id' => $listing->id,
            'quantity' => 1,
            'total_amount' => 1000,
            'status' => TransactionStatus::Pending,
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->adminToken())
            ->getJson("/api/admin/users?search={$target->email}")
            ->assertOk()
            ->assertJsonPath('data.users.0.reports_count', 2)
            ->assertJsonPath('data.users.0.pending_transactions_count', 1);
    }

    public function test_reactivation_requires_a_reason(): void
    {
        $user = User::factory()->create();
        $user->delete();
        $token = $this->adminToken();

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson("/api/admin/users/{$user->id}/reactivate", [])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('reason');

        $this->assertSoftDeleted('users', ['id' => $user->id]);
    }

    public function test_reactivation_restores_account_and_keeps_old_credentials_revoked(): void
    {
        $user = User::factory()->create([
            'email' => 'reactivate@example.com',
            'seller_capability' => SellerCapability::Buyer,
        ]);
        $oldToken = $user->createToken('mobile', ['mobile'])->plainTextToken;
        $token = $this->adminToken();

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->deleteJson("/api/admin/users/{$user->id}", [
                'reason' => 'Temporary account review.',
            ])
            ->assertOk();

        $this->withHeader('Authorization', 'Bearer '.$oldToken)
            ->getJson('/api/auth/me')
            ->assertUnauthorized();

        $this->postJson('/api/auth/login', [
            'email' => 'reactivate@example.com',
            'password' => 'password',
        ])->assertUnauthorized();

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson("/api/admin/users/{$user->id}/reactivate", [
                'reason' => 'Review completed; no violation found.',
            ])
            ->assertOk()
            ->assertJsonPath('data.status', 'active')
            ->assertJsonPath('data.deactivation_reason', null)
            ->assertJsonPath('data.deactivated_by', null);

        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'deleted_at' => null,
            'deactivation_reason' => null,
            'deactivated_by' => null,
        ]);

        $this->withHeader('Authorization', 'Bearer '.$oldToken)
            ->getJson('/api/auth/me')
            ->assertUnauthorized();

        $this->postJson('/api/auth/login', [
            'email' => 'reactivate@example.com',
            'password' => 'password',
        ])->assertOk();

        $activity = Activity::query()
            ->where('user_id', $this->admin->id)
            ->where('action', 'admin_user_reactivated')
            ->latest('id')
            ->firstOrFail();

        $this->assertSame(
            'Review completed; no violation found.',
            $activity->metadata['context']['reason'],
        );
    }

    public function test_reactivation_restores_eligible_seller_listing_visibility(): void
    {
        $seller = User::factory()->seller()->create();
        $listing = $this->activeListing($seller);
        $buyer = User::factory()->create();
        $buyerToken = $buyer->createToken('mobile', ['mobile'])->plainTextToken;
        $adminToken = $this->adminToken();

        $this->withHeader('Authorization', 'Bearer '.$adminToken)
            ->deleteJson("/api/admin/users/{$seller->id}", [
                'reason' => 'Temporary account review.',
            ])
            ->assertOk();

        $this->withHeader('Authorization', 'Bearer '.$buyerToken)
            ->getJson('/api/listings')
            ->assertOk()
            ->assertJsonMissing(['id' => $listing->id]);

        $this->withHeader('Authorization', 'Bearer '.$adminToken)
            ->postJson("/api/admin/users/{$seller->id}/reactivate", [
                'reason' => 'Review completed.',
            ])
            ->assertOk();

        $this->withHeader('Authorization', 'Bearer '.$buyerToken)
            ->getJson('/api/listings')
            ->assertOk()
            ->assertJsonPath('data.listings.0.id', $listing->id);

        $this->assertDatabaseHas('listings', [
            'id' => $listing->id,
            'status' => ListingStatus::Active->value,
        ]);
    }

    public function test_pending_transactions_and_reservations_are_untouched_by_deactivation(): void
    {
        $seller = User::factory()->seller()->create();
        $buyer = User::factory()->create();
        $listing = $this->activeListing($seller);

        $transaction = Transaction::create([
            'buyer_id' => $buyer->id,
            'seller_id' => $seller->id,
            'listing_id' => $listing->id,
            'quantity' => 1,
            'total_amount' => 1000,
            'status' => TransactionStatus::Pending,
            'inventory_reserved' => true,
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->adminToken())
            ->deleteJson("/api/admin/users/{$seller->id}", [
                'reason' => 'Temporary account review.',
            ])
            ->assertOk();

        $this->assertDatabaseHas('transactions', [
            'id' => $transaction->id,
            'status' => TransactionStatus::Pending->value,
            'inventory_reserved' => true,
        ]);
    }

    public function test_reactivation_rejects_an_active_or_missing_account(): void
    {
        $active = User::factory()->create();
        $token = $this->adminToken();

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson("/api/admin/users/{$active->id}/reactivate", [
                'reason' => 'Review completed.',
            ])
            ->assertStatus(409);

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->postJson('/api/admin/users/999999/reactivate', [
                'reason' => 'Review completed.',
            ])
            ->assertNotFound();
    }

    public function test_guest_and_regular_user_cannot_change_account_status(): void
    {
        $user = User::factory()->create();

        $this->deleteJson("/api/admin/users/{$user->id}", [
            'reason' => 'Policy violation confirmed.',
        ])->assertUnauthorized();

        $this->postJson("/api/admin/users/{$user->id}/reactivate", [
            'reason' => 'Review completed.',
        ])->assertUnauthorized();

        $regular = User::factory()->create();
        $token = $regular->createToken('mobile', ['mobile'])->plainTextToken;

        $this->withHeader('Authorization', 'Bearer '.$token)
            ->deleteJson("/api/admin/users/{$user->id}", [
                'reason' => 'Policy violation confirmed.',
            ])->assertForbidden();
    }
}
