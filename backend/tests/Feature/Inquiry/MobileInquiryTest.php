<?php

namespace Tests\Feature\Inquiry;

use App\Enums\ActivityAction;
use App\Enums\InquiryStatus;
use App\Enums\ListingStatus;
use App\Enums\UserRole;
use App\Models\Activity;
use App\Models\Inquiry;
use App\Models\Listing;
use App\Models\Message;
use App\Models\Transaction;
use App\Models\User;
use App\Repositories\Inquiry\InquiryRepository;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Mobile inquiry creation — `POST /api/inquiries` — and the buyer pre-check
 * `GET /api/inquiries/listing/{listing}`.
 *
 * The buyer's write path, as reserved by the `/admin/inquiries` route comment.
 * The rules under test are the ones the design document and the schema state:
 * the buyer and the seller are server-resolved, the inquiry is created `open`,
 * the message and both preferences are required, server-owned fields are
 * refused, one buyer may send only one inquiry per listing whatever its status,
 * and creating an inquiry changes nothing about the listing or the transaction
 * lifecycle.
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
     * A body the form could actually produce: message and both preferences.
     *
     * @param  array<string, mixed>  $overrides
     * @return array<string, mixed>
     */
    private function validInquiryBody(Listing $listing, array $overrides = []): array
    {
        $tomorrow = now()->addDay()->toDateString();

        return array_merge([
            'listing_id' => $listing->id,
            'message' => 'Is this one still available?',
            'collection_date_option' => 'next_few_days',
            'preferred_schedule' => $tomorrow,
            'payment_method' => 'cash',
            'collection_method' => 'farm_pickup',
        ], $overrides);
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

    private function getExisting(Listing $listing, ?User $user = null): TestResponse
    {
        return $this->withHeader(
            'Authorization',
            'Bearer '.$this->mobileToken($user ?? $this->buyer),
        )->getJson('/api/inquiries/listing/'.$listing->id);
    }

    #[Test]
    public function a_guest_cannot_send_an_inquiry(): void
    {
        $listing = $this->createListing($this->seller);

        $this->postJson('/api/inquiries', $this->validInquiryBody($listing))
            ->assertStatus(401);
    }

    #[Test]
    public function an_admin_token_is_refused(): void
    {
        $admin = User::factory()->create(['role' => UserRole::Admin]);
        $listing = $this->createListing($this->seller);

        $this->withHeader(
            'Authorization',
            'Bearer '.$admin->createToken('admin', ['admin'])->plainTextToken,
        )->postJson('/api/inquiries', $this->validInquiryBody($listing))
            ->assertStatus(403);
    }

    #[Test]
    public function a_message_with_both_preferences_is_a_valid_inquiry(): void
    {
        $listing = $this->createListing($this->seller);

        $body = $this->validInquiryBody($listing, [
            // `this_week` requires no date, so `preferred_schedule` stays null
            // and this test still verifies optional preferences are absent.
            'collection_date_option' => 'this_week',
        ]);
        unset($body['preferred_schedule']);

        $data = $this->postInquiry($body)
            ->assertStatus(201)
            ->json('data');

        $stored = Inquiry::query()->sole();

        // The three authority fields are server-resolved, never client-sent:
        // the buyer is the token, the seller is `listing.seller_id`, and the
        // status is the administrator's `open` bookmark.
        $this->assertSame($this->buyer->id, $stored->buyer_id);
        $this->assertSame($this->seller->id, $stored->seller_id);
        $this->assertSame('open', $stored->status->value);

        // The two required preferences are stored...
        $this->assertSame('cash', $stored->payment_method->value);
        $this->assertSame('farm_pickup', $stored->collection_method->value);

        // ...while every optional preference stays null when not sent.
        $this->assertNull($stored->purchase_interest);
        $this->assertNull($stored->transaction_method);
        $this->assertNull($stored->delivery_method);
        $this->assertNull($stored->delivery_fee);
        $this->assertNull($stored->contact_method);
        $this->assertNull($stored->preferred_schedule);

        $this->assertSame($listing->id, $data['listing']['id']);
        $this->assertSame('Is this one still available?', $data['message']);
        $this->assertSame('cash', $data['payment_method']);
        $this->assertSame('farm_pickup', $data['collection_method']);
    }

    #[Test]
    public function every_supported_preference_is_persisted_and_echoed(): void
    {
        $listing = $this->createListing($this->seller);

        $data = $this->postInquiry($this->validInquiryBody($listing, [
            'subject' => 'General Inquiry',
            'message' => 'Still available? I can pick it up this weekend.',
            'purchase_interest' => true,
            'transaction_method' => 'arrange_delivery',
            'delivery_method' => 'arrange_delivery',
            'delivery_fee' => '1500.50',
            'contact_method' => 'in_app_message',
            'preferred_schedule' => '2026-11-01',
            'payment_method' => 'gcash',
            'collection_method' => 'buyer_arranged_transportation',
        ]))->assertStatus(201)->json('data');

        $stored = Inquiry::query()->sole();

        $this->assertSame('General Inquiry', $stored->subject);
        $this->assertTrue($stored->purchase_interest);
        $this->assertSame('arrange_delivery', $stored->transaction_method->value);
        $this->assertSame('arrange_delivery', $stored->delivery_method);
        $this->assertSame('1500.50', (string) $stored->delivery_fee);
        $this->assertSame('in_app_message', $stored->contact_method->value);
        $this->assertSame('2026-11-01', $stored->preferred_schedule->toDateString());
        $this->assertSame('gcash', $stored->payment_method->value);
        $this->assertSame('buyer_arranged_transportation', $stored->collection_method->value);

        $this->assertSame('General Inquiry', $data['subject']);
        $this->assertTrue($data['purchase_interest']);
        $this->assertSame('arrange_delivery', $data['transaction_method']);
        $this->assertSame('arrange_delivery', $data['delivery_method']);
        $this->assertSame('1500.50', $data['delivery_fee']);
        $this->assertSame('in_app_message', $data['contact_method']);
        $this->assertSame('2026-11-01', $data['preferred_schedule']);
        $this->assertSame('gcash', $data['payment_method']);
        $this->assertSame('buyer_arranged_transportation', $data['collection_method']);
    }

    #[Test]
    public function the_response_carries_no_status_and_no_contact_details(): void
    {
        $listing = $this->createListing($this->seller);

        $data = $this->postInquiry($this->validInquiryBody($listing))
            ->assertStatus(201)
            ->json('data');

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
            $this->postInquiry($this->validInquiryBody($listing, [
                $field => 'x',
            ]))->assertStatus(422);
        }

        $this->assertSame(0, Inquiry::query()->count());
    }

    #[Test]
    public function a_non_active_listing_cannot_be_inquired(): void
    {
        $listing = $this->createListing($this->seller, ['status' => ListingStatus::Pending]);

        $this->postInquiry($this->validInquiryBody($listing))
            ->assertStatus(409);

        $this->assertSame(0, Inquiry::query()->count());
    }

    #[Test]
    public function a_seller_cannot_inquire_about_their_own_listing(): void
    {
        $listing = $this->createListing($this->seller);

        $this->postInquiry($this->validInquiryBody($listing), $this->seller)
            ->assertStatus(409);

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
            'payment_method' => 'cash',
            'collection_method' => 'farm_pickup',
        ])->assertStatus(422)->assertJsonValidationErrors(['listing_id']);
    }

    #[Test]
    public function a_missing_message_is_refused(): void
    {
        $listing = $this->createListing($this->seller);

        $body = $this->validInquiryBody($listing);
        unset($body['message']);

        $this->postInquiry($body)
            ->assertStatus(422)
            ->assertJsonValidationErrors(['message']);
    }

    #[Test]
    public function a_missing_payment_method_is_refused(): void
    {
        $listing = $this->createListing($this->seller);

        $body = $this->validInquiryBody($listing);
        unset($body['payment_method']);

        $this->postInquiry($body)
            ->assertStatus(422)
            ->assertJsonValidationErrors(['payment_method']);

        $this->assertSame(0, Inquiry::query()->count());
    }

    #[Test]
    public function a_missing_collection_method_is_refused(): void
    {
        $listing = $this->createListing($this->seller);

        $body = $this->validInquiryBody($listing);
        unset($body['collection_method']);

        $this->postInquiry($body)
            ->assertStatus(422)
            ->assertJsonValidationErrors(['collection_method']);

        $this->assertSame(0, Inquiry::query()->count());
    }

    #[Test]
    public function a_whitespace_only_message_is_refused(): void
    {
        $listing = $this->createListing($this->seller);

        $this->postInquiry($this->validInquiryBody($listing, [
            'message' => "   \n  ",
        ]))->assertStatus(422)->assertJsonValidationErrors(['message']);

        $this->assertSame(0, Inquiry::query()->count());
    }

    #[Test]
    public function a_message_over_500_characters_is_refused(): void
    {
        $listing = $this->createListing($this->seller);

        $this->postInquiry($this->validInquiryBody($listing, [
            'message' => str_repeat('a', 501),
        ]))->assertStatus(422)->assertJsonValidationErrors(['message']);

        $this->assertSame(0, Inquiry::query()->count());
    }

    #[Test]
    public function malformed_preferences_are_refused(): void
    {
        $listing = $this->createListing($this->seller);

        $this->postInquiry($this->validInquiryBody($listing, [
            'transaction_method' => 'carrier_pigeon',
        ]))->assertStatus(422)->assertJsonValidationErrors(['transaction_method']);

        $this->postInquiry($this->validInquiryBody($listing, [
            'contact_method' => 'phone_call',
        ]))->assertStatus(422)->assertJsonValidationErrors(['contact_method']);

        $this->postInquiry($this->validInquiryBody($listing, [
            'delivery_fee' => -1,
        ]))->assertStatus(422)->assertJsonValidationErrors(['delivery_fee']);

        $this->postInquiry($this->validInquiryBody($listing, [
            'purchase_interest' => 'maybe',
        ]))->assertStatus(422)->assertJsonValidationErrors(['purchase_interest']);

        $this->postInquiry($this->validInquiryBody($listing, [
            'payment_method' => 'bank_transfer',
        ]))->assertStatus(422)->assertJsonValidationErrors(['payment_method']);

        $this->postInquiry($this->validInquiryBody($listing, [
            'collection_method' => 'courier',
        ]))->assertStatus(422)->assertJsonValidationErrors(['collection_method']);

        $this->assertSame(0, Inquiry::query()->count());
    }

    #[Test]
    public function a_second_inquiry_for_the_same_listing_is_a_conflict(): void
    {
        $listing = $this->createListing($this->seller);

        $this->postInquiry($this->validInquiryBody($listing))->assertStatus(201);

        $this->postInquiry($this->validInquiryBody($listing, [
            'message' => 'Asking a second time.',
        ]))->assertStatus(409)
            ->assertJson([
                'message' => 'You have already sent an inquiry about this listing.',
            ]);

        $this->assertSame(1, Inquiry::query()->count());
    }

    #[Test]
    public function a_duplicate_is_refused_whatever_the_existing_status(): void
    {
        $listing = $this->createListing($this->seller);

        Inquiry::create([
            'buyer_id' => $this->buyer->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'message' => 'An inquiry the administrator has since closed.',
            'status' => InquiryStatus::Closed,
        ]);

        $this->postInquiry($this->validInquiryBody($listing))
            ->assertStatus(409);

        $this->assertSame(1, Inquiry::query()->count());
    }

    #[Test]
    public function different_buyers_may_inquire_about_the_same_listing(): void
    {
        $listing = $this->createListing($this->seller);

        $this->postInquiry($this->validInquiryBody($listing))->assertStatus(201);
        $this->postInquiry($this->validInquiryBody($listing), $this->stranger)
            ->assertStatus(201);

        $this->assertSame(2, Inquiry::query()->count());
    }

    #[Test]
    public function a_concurrent_duplicate_is_a_conflict_not_a_server_error(): void
    {
        $listing = $this->createListing($this->seller);

        $existing = Inquiry::create([
            'buyer_id' => $this->buyer->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'message' => 'Inserted by the request that won the race.',
            'status' => InquiryStatus::Open,
        ]);

        // Simulate the race: the pre-check sees nothing, the insert hits the
        // unique index, and the follow-up lookup sees the row the other
        // request committed.
        $violation = new QueryException(
            'sqlite',
            'insert into "inquiries" ("buyer_id", "listing_id") values (?, ?)',
            [$this->buyer->id, $listing->id],
            new \RuntimeException('UNIQUE constraint failed: inquiries.buyer_id, inquiries.listing_id'),
        );

        $this->mock(InquiryRepository::class, function ($mock) use ($existing, $violation): void {
            $mock->shouldReceive('findForBuyerAndListing')
                ->twice()
                ->andReturn(null, $existing);
            $mock->shouldReceive('create')->once()->andThrow($violation);
        });

        $this->postInquiry($this->validInquiryBody($listing))
            ->assertStatus(409)
            ->assertJson([
                'message' => 'You have already sent an inquiry about this listing.',
            ]);

        $this->assertSame(1, Inquiry::query()->count());
    }

    #[Test]
    public function the_database_rejects_a_second_inquiry_for_the_same_pair(): void
    {
        $listing = $this->createListing($this->seller);

        $this->postInquiry($this->validInquiryBody($listing))->assertStatus(201);

        // The service is the ordinary guard; this proves the index behind it
        // holds even when a writer bypasses the service.
        $this->expectException(QueryException::class);

        Inquiry::create([
            'buyer_id' => $this->buyer->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'message' => 'A second row for the same pair.',
            'status' => InquiryStatus::Open,
        ]);
    }

    #[Test]
    public function the_existing_inquiry_endpoint_returns_the_buyers_own_inquiry(): void
    {
        $listing = $this->createListing($this->seller);

        $this->postInquiry($this->validInquiryBody($listing, [
            'message' => 'Already asked.',
        ]))->assertStatus(201);

        $this->getExisting($listing)
            ->assertStatus(200)
            ->assertJsonPath('data.message', 'Already asked.')
            ->assertJsonPath('data.payment_method', 'cash')
            ->assertJsonPath('data.collection_method', 'farm_pickup');
    }

    #[Test]
    public function the_existing_inquiry_endpoint_returns_null_when_none_exists(): void
    {
        $listing = $this->createListing($this->seller);

        $this->getExisting($listing)
            ->assertStatus(200)
            ->assertJsonPath('data', null);
    }

    #[Test]
    public function the_existing_inquiry_endpoint_is_scoped_to_the_buyer(): void
    {
        $listing = $this->createListing($this->seller);

        $this->postInquiry($this->validInquiryBody($listing))->assertStatus(201);

        // The stranger has sent nothing, so the buyer's record is invisible.
        $this->getExisting($listing, $this->stranger)
            ->assertStatus(200)
            ->assertJsonPath('data', null);
    }

    #[Test]
    public function the_existing_inquiry_endpoint_returns_a_closed_inquiry(): void
    {
        $listing = $this->createListing($this->seller);

        Inquiry::create([
            'buyer_id' => $this->buyer->id,
            'seller_id' => $this->seller->id,
            'listing_id' => $listing->id,
            'message' => 'Closed, but still mine.',
            'status' => InquiryStatus::Closed,
        ]);

        // Status does not hide the record from the pre-check: the buyer still
        // must not be offered a second form.
        $this->getExisting($listing)
            ->assertStatus(200)
            ->assertJsonPath('data.message', 'Closed, but still mine.');
    }

    #[Test]
    public function the_existing_inquiry_endpoint_requires_authentication(): void
    {
        $listing = $this->createListing($this->seller);

        $this->getJson('/api/inquiries/listing/'.$listing->id)
            ->assertStatus(401);
    }

    #[Test]
    public function sending_an_inquiry_changes_nothing_else(): void
    {
        $listing = $this->createListing($this->seller);

        $this->postInquiry($this->validInquiryBody($listing, [
            'message' => 'Still available? I am interested.',
            'purchase_interest' => true,
        ]))->assertStatus(201);

        // A message of record: no lifecycle change, no transaction, nothing
        // sold or reserved.
        $this->assertSame(ListingStatus::Active, $listing->refresh()->status);
        $this->assertSame(0, Transaction::query()->count());
    }

    #[Test]
    public function creation_is_audited(): void
    {
        $listing = $this->createListing($this->seller);

        $this->postInquiry($this->validInquiryBody($listing))->assertStatus(201);

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

    #[Test]
    public function collection_date_option_is_required(): void
    {
        $listing = $this->createListing($this->seller);

        $body = $this->validInquiryBody($listing);
        unset($body['collection_date_option']);

        $this->postInquiry($body)
            ->assertStatus(422)
            ->assertJsonValidationErrors(['collection_date_option']);

        $this->assertSame(0, Inquiry::query()->count());
    }

    #[Test]
    public function specific_date_requires_preferred_schedule(): void
    {
        $listing = $this->createListing($this->seller);

        $body = $this->validInquiryBody($listing, [
            'collection_date_option' => 'specific_date',
        ]);
        unset($body['preferred_schedule']);

        $this->postInquiry($body)
            ->assertStatus(422)
            ->assertJsonValidationErrors(['preferred_schedule']);

        $this->assertSame(0, Inquiry::query()->count());
    }

    #[Test]
    public function past_preferred_schedule_is_refused(): void
    {
        $listing = $this->createListing($this->seller);

        $this->postInquiry($this->validInquiryBody($listing, [
            'collection_date_option' => 'specific_date',
            'preferred_schedule' => '2020-01-01',
        ]))->assertStatus(422)
            ->assertJsonValidationErrors(['preferred_schedule']);

        $this->assertSame(0, Inquiry::query()->count());
    }

    #[Test]
    public function relative_collection_date_options_handle_dates_correctly(): void
    {
        $tomorrow = now()->addDay()->toDateString();
        $day4 = now()->addDays(4)->toDateString();

        // `this_week` requires no date.
        $listing = $this->createListing($this->seller);
        $body = $this->validInquiryBody($listing, [
            'collection_date_option' => 'this_week',
        ]);
        unset($body['preferred_schedule']);
        $this->postInquiry($body)->assertStatus(201);
        $this->assertSame('this_week', Inquiry::query()
            ->where('listing_id', $listing->id)
            ->sole()->collection_date_option);
        $this->assertNull(Inquiry::query()->sole()->preferred_schedule);

        // `next_few_days` requires a date between tomorrow and today + 3 days.
        $listing2 = $this->createListing($this->seller);
        $body = $this->validInquiryBody($listing2, [
            'collection_date_option' => 'next_few_days',
        ]);
        unset($body['preferred_schedule']);
        $this->postInquiry($body)
            ->assertStatus(422)
            ->assertJsonValidationErrors(['preferred_schedule']);

        $this->postInquiry($this->validInquiryBody($listing2, [
            'collection_date_option' => 'next_few_days',
            'preferred_schedule' => $tomorrow,
        ]))->assertStatus(201);

        $this->assertSame('next_few_days', Inquiry::query()
            ->where('listing_id', $listing2->id)
            ->sole()->collection_date_option);
        $this->assertSame($tomorrow, Inquiry::query()
            ->where('listing_id', $listing2->id)
            ->sole()->preferred_schedule->toDateString());

        // A date 4 days out is rejected for `next_few_days`.
        $listing3 = $this->createListing($this->seller);
        $this->postInquiry($this->validInquiryBody($listing3, [
            'collection_date_option' => 'next_few_days',
            'preferred_schedule' => $day4,
        ]))->assertStatus(422)
            ->assertJsonValidationErrors(['preferred_schedule']);
    }

    #[Test]
    public function creating_an_inquiry_creates_the_initial_message_in_the_same_transaction(): void
    {
        $listing = $this->createListing($this->seller);

        $this->postInquiry($this->validInquiryBody($listing, [
            'message' => 'Still available? I am interested.',
        ]))->assertStatus(201);

        $this->assertSame(1, Message::query()->count());

        $message = Message::query()->sole();
        $this->assertSame($this->buyer->id, $message->sender_id);
        $this->assertSame($this->seller->id, $message->receiver_id);
        $this->assertSame($listing->id, $message->listing_id);
        $this->assertStringContainsString($listing->displayLabel(), $message->body);
        $this->assertStringContainsString('Still available? I am interested.', $message->body);
    }

    #[Test]
    public function inquiry_response_returns_conversation_counterpart_id(): void
    {
        $listing = $this->createListing($this->seller);

        $data = $this->postInquiry($this->validInquiryBody($listing))
            ->assertStatus(201)
            ->json('data');

        $this->assertSame($this->seller->id, $data['conversation_counterpart_id']);
    }

    #[Test]
    public function duplicate_inquiry_creates_no_second_message(): void
    {
        $listing = $this->createListing($this->seller);

        $this->postInquiry($this->validInquiryBody($listing))->assertStatus(201);

        $this->postInquiry($this->validInquiryBody($listing, [
            'message' => 'Asking a second time.',
        ]))->assertStatus(409);

        $this->assertSame(1, Inquiry::query()->count());
        $this->assertSame(1, Message::query()->count());
    }

    #[Test]
    public function seller_sees_collection_date_option_in_received_inquiries(): void
    {
        // Covered by SellerInquiryResource; this test keeps the mobile
        // projection contract visible here alongside the buyer flow.
        $listing = $this->createListing($this->seller);

        $this->postInquiry($this->validInquiryBody($listing, [
            'collection_date_option' => 'specific_date',
            'preferred_schedule' => '2026-12-01',
        ]))->assertStatus(201);

        $this->assertSame('specific_date', Inquiry::query()->sole()->collection_date_option);
        $this->assertSame('2026-12-01', Inquiry::query()->sole()->preferred_schedule->toDateString());
    }
}
