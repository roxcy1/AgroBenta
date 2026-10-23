<?php

namespace Tests\Feature\Inquiry;

use App\Enums\ActivityAction;
use App\Enums\ListingStatus;
use App\Enums\UserRole;
use App\Models\Activity;
use App\Models\Inquiry;
use App\Models\Listing;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Mobile inquiry creation — `POST /api/inquiries`.
 *
 * The buyer's write path, as reserved by the `/admin/inquiries` route
 * comment. The rules under test are the ones the design document and the
 * schema state: the buyer and the seller are server-resolved, the inquiry is
 * created `open`, a plain message is a valid inquiry, the structured
 * preferences are optional, server-owned fields are refused, and creating an
 * inquiry changes nothing about the listing or the transaction lifecycle.
 */
class MobileInquiryTest extends TestCase
{
    use RefreshDatabase;

    private User $buyer;

    private User $seller;

    private User $stranger;

    protected function setUp(): void
    {
        parent::setUp();

        $this->buyer = User::factory()->create([
            'role' => UserRole::User,
            'name' => 'Pedro Reyes',
        ]);

        $this->seller = User::factory()->seller()->create([
            'role' => UserRole::User,
            'name' => 'Juan Dela Cruz',
            'email' => 'juan@agrobenta.test',
        ]);

        $this->stranger = User::factory()->create([
            'role' => UserRole::User,
            'name' => 'Ramon Cruz',
        ]);
    }

    private function mobileToken(User $user): string
    {
        return $user->createToken('mobile', ['mobile'])->plainTextToken;
    }

    /**
     * @param  array<string, mixed>  $overrides
     */
    private function createListing(User $seller, array $overrides = []): Listing
    {
        return Listing::create(array_merge([
            'seller_id' => $seller->id,
            'livestock_type' => 'cattle',
            'breed' => 'Angus',
            'age_value' => 2,
            'age_unit' => 'year',
            'gender' => 'male',
            'weight_value' => 500,
            'weight_unit' => 'kg',
            'quantity' => 5,
            'asking_price' => 50000.00,
            'location' => 'Bukidnon',
            'health_status' => 'healthy',
            'vaccination' => 'up_to_date',
            'short_description' => 'Healthy Angus bull',
            'additional_notes' => null,
            'photos' => [],
            'status' => ListingStatus::Active,
        ], $overrides));
    }

    /**
     * @param  array<string, mixed>  $body
     */
    private function postInquiry(array $body, ?User $user = null): TestResponse
    {
        return $this->withHeader(
            'Authorization',
            'Bearer '.$this->mobileToken($user ?? $this->buyer),
        )->postJson('/api/inquiries', $body);
    }

    #[Test]
    public function a_guest_cannot_send_an_inquiry(): void
    {
        $listing = $this->createListing($this->seller);

        $this->postJson('/api/inquiries', [
            'listing_id' => $listing->id,
            'message' => 'Is this one still available?',
        ])->assertStatus(401);
    }

    #[Test]
    public function an_admin_token_is_refused(): void
    {
        $admin = User::factory()->create(['role' => UserRole::Admin]);
        $listing = $this->createListing($this->seller);

        $this->withHeader(
            'Authorization',
            'Bearer '.$admin->createToken('admin', ['admin'])->plainTextToken,
        )->postJson('/api/inquiries', [
            'listing_id' => $listing->id,
            'message' => 'Is this one still available?',
        ])->assertStatus(403);
    }

    #[Test]
    public function a_plain_message_is_a_valid_inquiry(): void
    {
        $listing = $this->createListing($this->seller);

        $data = $this->postInquiry([
            'listing_id' => $listing->id,
            'message' => 'Is this one still available?',
        ])->assertStatus(201)->json('data');

        $stored = Inquiry::query()->sole();

        // The three authority fields are server-resolved, never client-sent:
        // the buyer is the token, the seller is `listing.seller_id`, and the
        // status is the administrator's `open` bookmark.
        $this->assertSame($this->buyer->id, $stored->buyer_id);
        $this->assertSame($this->seller->id, $stored->seller_id);
        $this->assertSame('open', $stored->status->value);

        // Every preference column stays null when the form did not send one.
        $this->assertNull($stored->purchase_interest);
        $this->assertNull($stored->transaction_method);
        $this->assertNull($stored->delivery_method);
        $this->assertNull($stored->delivery_fee);
        $this->assertNull($stored->contact_method);
        $this->assertNull($stored->preferred_schedule);

        $this->assertSame($listing->id, $data['listing']['id']);
        $this->assertSame('Is this one still available?', $data['message']);
    }

    #[Test]
    public function every_supported_preference_is_persisted_and_echoed(): void
    {
        $listing = $this->createListing($this->seller);

        $data = $this->postInquiry([
            'listing_id' => $listing->id,
            'subject' => 'General Inquiry',
            'message' => 'Still available? I can pick it up this weekend.',
            'purchase_interest' => true,
            'transaction_method' => 'arrange_delivery',
            'delivery_method' => 'arrange_delivery',
            'delivery_fee' => '1500.50',
            'contact_method' => 'in_app_message',
            'preferred_schedule' => '2026-11-01',
        ])->assertStatus(201)->json('data');

        $stored = Inquiry::query()->sole();

        $this->assertSame('General Inquiry', $stored->subject);
        $this->assertTrue($stored->purchase_interest);
        $this->assertSame('arrange_delivery', $stored->transaction_method->value);
        $this->assertSame('arrange_delivery', $stored->delivery_method);
        $this->assertSame('1500.50', (string) $stored->delivery_fee);
        $this->assertSame('in_app_message', $stored->contact_method->value);
        $this->assertSame('2026-11-01', $stored->preferred_schedule->toDateString());

        $this->assertSame('General Inquiry', $data['subject']);
        $this->assertTrue($data['purchase_interest']);
        $this->assertSame('arrange_delivery', $data['transaction_method']);
        $this->assertSame('arrange_delivery', $data['delivery_method']);
        $this->assertSame('1500.50', $data['delivery_fee']);
        $this->assertSame('in_app_message', $data['contact_method']);
        $this->assertSame('2026-11-01', $data['preferred_schedule']);
    }

    #[Test]
    public function the_response_carries_no_status_and_no_contact_details(): void
    {
        $listing = $this->createListing($this->seller);

        $data = $this->postInquiry([
            'listing_id' => $listing->id,
            'message' => 'Still available?',
        ])->assertStatus(201)->json('data');

        // The workflow status is an administrator bookmark the buyer never
        // sees, and neither party's email belongs in a mobile projection.
        $this->assertArrayNotHasKey('status', $data);
        $this->assertArrayNotHasKey('buyer', $data);
        $this->assertArrayNotHasKey('seller', $data);
        $this->assertArrayNotHasKey('email', $data['listing'] ?? []);
    }

    #[Test]
    public function server_owned_create_fields_are_rejected(): void
    {
        $listing = $this->createListing($this->seller);

        foreach (['buyer_id', 'seller_id', 'status'] as $field) {
            $this->postInquiry([
                'listing_id' => $listing->id,
                'message' => 'Still available?',
                $field => 'x',
            ])->assertStatus(422);
        }

        $this->assertSame(0, Inquiry::query()->count());
    }

    #[Test]
    public function a_non_active_listing_cannot_be_inquired(): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Pending]);

        $this->postInquiry([
            'listing_id' => $listing->id,
            'message' => 'Still available?',
        ])->assertStatus(409);

        $this->assertSame(0, Inquiry::query()->count());
    }

    #[Test]
    public function a_seller_cannot_inquire_about_their_own_listing(): void
    {
        $listing = $this->createListing($this->seller);

        $this->postInquiry([
            'listing_id' => $listing->id,
            'message' => 'Still available?',
        ], $this->seller)->assertStatus(409);

        $this->assertSame(0, Inquiry::query()->count());
    }

    #[Test]
    public function an_unknown_listing_is_a_validation_error(): void
    {
        // `exists:listings,id` runs before any lookup, so an id that never
        // existed answers 422 — the same shape as every other bad field.
        $this->postInquiry([
            'listing_id' => 999999,
            'message' => 'Still available?',
        ])->assertStatus(422)->assertJsonValidationErrors(['listing_id']);
    }

    #[Test]
    public function a_missing_message_is_refused(): void
    {
        $listing = $this->createListing($this->seller);

        $this->postInquiry([
            'listing_id' => $listing->id,
        ])->assertStatus(422)->assertJsonValidationErrors(['message']);
    }

    #[Test]
    public function a_whitespace_only_message_is_refused(): void
    {
        $listing = $this->createListing($this->seller);

        $this->postInquiry([
            'listing_id' => $listing->id,
            'message' => "   \n  ",
        ])->assertStatus(422)->assertJsonValidationErrors(['message']);

        $this->assertSame(0, Inquiry::query()->count());
    }

    #[Test]
    public function a_message_over_500_characters_is_refused(): void
    {
        $listing = $this->createListing($this->seller);

        $this->postInquiry([
            'listing_id' => $listing->id,
            'message' => str_repeat('a', 501),
        ])->assertStatus(422)->assertJsonValidationErrors(['message']);

        $this->assertSame(0, Inquiry::query()->count());
    }

    #[Test]
    public function malformed_preferences_are_refused(): void
    {
        $listing = $this->createListing($this->seller);

        $this->postInquiry([
            'listing_id' => $listing->id,
            'message' => 'Still available?',
            'transaction_method' => 'carrier_pigeon',
        ])->assertStatus(422)->assertJsonValidationErrors(['transaction_method']);

        $this->postInquiry([
            'listing_id' => $listing->id,
            'message' => 'Still available?',
            'contact_method' => 'phone_call',
        ])->assertStatus(422)->assertJsonValidationErrors(['contact_method']);

        $this->postInquiry([
            'listing_id' => $listing->id,
            'message' => 'Still available?',
            'delivery_fee' => -1,
        ])->assertStatus(422)->assertJsonValidationErrors(['delivery_fee']);

        $this->postInquiry([
            'listing_id' => $listing->id,
            'message' => 'Still available?',
            'purchase_interest' => 'maybe',
        ])->assertStatus(422)->assertJsonValidationErrors(['purchase_interest']);
    }

    #[Test]
    public function sending_an_inquiry_changes_nothing_else(): void
    {
        $listing = $this->createListing($this->seller);

        $this->postInquiry([
            'listing_id' => $listing->id,
            'message' => 'Still available? I am interested.',
            'purchase_interest' => true,
        ])->assertStatus(201);

        // A message of record: no lifecycle change, no transaction, nothing
        // sold or reserved.
        $this->assertSame(ListingStatus::Active, $listing->refresh()->status);
        $this->assertSame(0, Transaction::query()->count());
    }

    #[Test]
    public function creation_is_audited(): void
    {
        $listing = $this->createListing($this->seller);

        $this->postInquiry([
            'listing_id' => $listing->id,
            'message' => 'Still available?',
        ])->assertStatus(201);

        $activity = Activity::query()
            ->where('action', ActivityAction::InquiryCreated->value)
            ->sole();

        $this->assertSame($this->buyer->id, $activity->user_id);
        $this->assertSame(
            Inquiry::query()->sole()->id,
            (int) ($activity->metadata['target_id'] ?? 0),
        );
        $this->assertSame($listing->id, (int) ($activity->metadata['context']['listing_id'] ?? 0));
    }
}
