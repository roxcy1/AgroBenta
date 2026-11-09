<?php

namespace Tests\Feature\Offer;

use App\Enums\ListingStatus;
use App\Enums\UserRole;
use App\Models\Inquiry;
use App\Models\Listing;
use App\Models\Offer;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Purchase offers â€” `POST /api/offers`, `GET /api/offers/{offer}`,
 * `POST /api/offers/{offer}/accept`, `/decline`, `/withdraw`.
 *
 * Rules under test:
 *  - the buyer and seller are server-resolved, never client-sent;
 *  - only the listing's seller (an approved seller) may create an offer;
 *  - only the inquiry's buyer may accept or decline;
 *  - only the creating seller may withdraw;
 *  - `pending` is the only actionable state; a second acceptance cannot
 *    create a second transaction;
 *  - accepting an offer creates exactly one `pending` transaction whose
 *    `total_amount` is the agreed `proposed_amount`.
 */
class OfferTest extends TestCase
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

        $this->stranger = User::factory()->seller()->create([
            'role' => UserRole::User,
            'name' => 'Ramon Cruz',
        ]);
    }

    private function mobileToken(User $user): string
    {
        return $user->createToken('mobile', ['mobile'])->plainTextToken;
    }

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
     * @param  array<string, mixed>  $overrides
     */
    private function createInquiry(
        User $buyer,
        User $seller,
        Listing $listing,
        array $overrides = []
    ): Inquiry {
        return Inquiry::create(array_merge([
            'buyer_id' => $buyer->id,
            'seller_id' => $seller->id,
            'listing_id' => $listing->id,
            'subject' => 'Is this still available?',
            'message' => 'I would like to buy this animal.',
            'status' => 'open',
        ], $overrides));
    }

    /**
     * @param  array<string, mixed>  $body
     */
    private function postOffer(array $body, ?User $user = null): TestResponse
    {
        return $this->withHeader(
            'Authorization',
            'Bearer '.$this->mobileToken($user ?? $this->seller),
        )->postJson('/api/offers', $body);
    }

    private function postOfferAction(
        string $action,
        int $offerId,
        ?User $user = null
    ): TestResponse {
        return $this->withHeader(
            'Authorization',
            'Bearer '.$this->mobileToken($user ?? $this->buyer),
        )->postJson('/api/offers/'.$offerId.'/'.$action);
    }

    private function getOffer(int $offerId, ?User $user = null): TestResponse
    {
        return $this->withHeader(
            'Authorization',
            'Bearer '.$this->mobileToken($user ?? $this->buyer),
        )->getJson('/api/offers/'.$offerId);
    }

    /**
     * @param  array<string, mixed>  $query
     */
    private function getOffers(array $query = [], ?User $user = null): TestResponse
    {
        return $this->withHeader(
            'Authorization',
            'Bearer '.$this->mobileToken($user ?? $this->buyer),
        )->getJson('/api/offers?'.http_build_query($query));
    }

    #[Test]
    public function a_guest_cannot_create_an_offer(): void
    {
        $listing = $this->createListing($this->seller);
        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing);

        $this->postJson('/api/offers', [
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 48000.00,
        ])->assertStatus(401);
    }

    #[Test]
    public function a_non_seller_cannot_create_an_offer(): void
    {
        $listing = $this->createListing($this->seller);
        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing);

        // The caller is the buyer â€” not an approved seller.
        $this->postOffer([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 48000.00,
        ], $this->buyer)->assertStatus(403);
    }

    #[Test]
    public function a_stranger_cannot_create_an_offer_for_another_listing(): void
    {
        $listing = $this->createListing($this->seller);
        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing);

        // The stranger is an approved seller but does not own this listing.
        $this->postOffer([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 48000.00,
        ], $this->stranger)->assertStatus(409);
    }

    #[Test]
    public function a_seller_can_create_a_purchase_offer(): void
    {
        $listing = $this->createListing($this->seller);
        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing);

        $data = $this->postOffer([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 48000.00,
        ])->assertStatus(201)->json('data');

        $stored = Offer::query()->sole();

        $this->assertSame($inquiry->id, $stored->inquiry_id);
        $this->assertSame($listing->id, $stored->listing_id);
        $this->assertSame($this->seller->id, $stored->seller_id);
        $this->assertSame($this->buyer->id, $stored->buyer_id);
        $this->assertSame('48000.00', $stored->proposed_amount);
        $this->assertSame('pending', $stored->status->value);
        $this->assertNull($stored->responded_at);

        $this->assertSame($inquiry->id, $data['inquiry_id']);
        $this->assertSame('48000.00', $data['proposed_amount']);
        $this->assertSame('pending', $data['status']);
    }

    #[Test]
    public function an_inquiry_can_have_only_one_pending_offer(): void
    {
        $listing = $this->createListing($this->seller);
        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing);

        $this->postOffer([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 48000.00,
        ])->assertStatus(201);

        $this->postOffer([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 47000.00,
        ])->assertStatus(409);

        $this->assertSame(1, Offer::query()->count());
    }

    #[Test]
    public function the_buyer_can_accept_a_pending_offer_and_it_creates_one_transaction(): void
    {
        $listing = $this->createListing($this->seller);
        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing);

        $offerId = $this->postOffer([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 48000.00,
        ])->assertStatus(201)->json('data.id');

        $response = $this->postOfferAction('accept', $offerId, $this->buyer)
            ->assertStatus(200)
            ->json('data');

        $offer = Offer::query()->sole();
        $this->assertSame('accepted', $offer->status->value);
        $this->assertNotNull($offer->responded_at);

        $transaction = Transaction::query()->sole();
        $this->assertSame('pending', $transaction->status->value);
        $this->assertSame($this->buyer->id, $transaction->buyer_id);
        $this->assertSame($this->seller->id, $transaction->seller_id);
        $this->assertSame($listing->id, $transaction->listing_id);
        $this->assertSame('48000.00', $transaction->total_amount);

        $this->assertSame('accepted', $response['offer']['status']);
        $this->assertSame($transaction->id, $response['transaction']['id']);
        $this->assertSame('pending', $response['transaction']['status']);
        $this->assertSame('48000.00', $response['transaction']['total_amount']);
        $this->assertSame('buyer', $response['transaction']['role']);
        $this->assertSame($listing->id, $response['transaction']['listing']['id']);
        $this->assertSame($this->seller->id, $response['transaction']['counterparty']['id']);
    }

    #[Test]
    public function a_duplicate_acceptance_creates_no_second_transaction(): void
    {
        $listing = $this->createListing($this->seller);
        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing);

        $offerId = $this->postOffer([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 48000.00,
        ])->assertStatus(201)->json('data.id');

        $this->postOfferAction('accept', $offerId, $this->buyer)->assertStatus(200);
        $this->postOfferAction('accept', $offerId, $this->buyer)->assertStatus(409);

        $this->assertSame(1, Offer::query()->count());
        $this->assertSame(1, Transaction::query()->count());
        $this->assertSame('accepted', Offer::query()->sole()->status->value);
    }

    /**
     * @return array<string, array{array<string, mixed>}>
     */
    public static function listingChangesThatBlockAcceptance(): array
    {
        return [
            'sold' => [['status' => ListingStatus::Sold]],
            'inactive' => [['status' => ListingStatus::Inactive]],
            'out of stock' => [['quantity' => 0]],
        ];
    }

    /**
     * An offer can be days old. If the listing was sold, deactivated or ran out
     * of stock since, accepting it must be refused exactly as a direct purchase
     * of that listing would be, and must not leave a transaction behind.
     *
     * @param  array<string, mixed>  $change
     */
    #[Test]
    #[DataProvider('listingChangesThatBlockAcceptance')]
    public function accepting_an_offer_is_refused_once_the_listing_is_no_longer_available(array $change): void
    {
        $listing = $this->createListing($this->seller, ['quantity' => 1]);
        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing);

        $offerId = $this->postOffer([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 48000.00,
        ])->assertStatus(201)->json('data.id');

        $listing->forceFill($change)->save();

        $this->postOfferAction('accept', $offerId, $this->buyer)->assertStatus(409);

        $this->assertSame(0, Transaction::query()->count());
        $this->assertSame('pending', Offer::query()->findOrFail($offerId)->status->value);

        // Still pending, so the seller can clear it up.
        $this->postOfferAction('withdraw', $offerId, $this->seller)->assertStatus(200);
        $this->assertSame('withdrawn', Offer::query()->findOrFail($offerId)->status->value);
    }

    #[Test]
    public function the_last_unit_can_still_be_accepted(): void
    {
        $listing = $this->createListing($this->seller, ['quantity' => 1]);
        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing);

        $offerId = $this->postOffer([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 48000.00,
        ])->assertStatus(201)->json('data.id');

        $this->postOfferAction('accept', $offerId, $this->buyer)->assertStatus(200);

        $this->assertSame(1, Transaction::query()->count());
    }

    #[Test]
    public function only_the_buyer_may_accept_an_offer(): void
    {
        $listing = $this->createListing($this->seller);
        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing);

        $offerId = $this->postOffer([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 48000.00,
        ])->assertStatus(201)->json('data.id');

        // The seller is a party but not the buyer, so acceptance is refused
        // with 409 (not 404 â€” 404 is only for a non-party).
        $this->postOfferAction('accept', $offerId, $this->seller)
            ->assertStatus(409);

        $this->assertSame('pending', Offer::query()->sole()->status->value);
        $this->assertSame(0, Transaction::query()->count());
    }

    #[Test]
    public function the_buyer_can_decline_a_pending_offer(): void
    {
        $listing = $this->createListing($this->seller);
        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing);

        $offerId = $this->postOffer([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 48000.00,
        ])->assertStatus(201)->json('data.id');

        $this->postOfferAction('decline', $offerId, $this->buyer)
            ->assertStatus(200);

        $this->assertSame('declined', Offer::query()->sole()->status->value);
    }

    #[Test]
    public function the_seller_can_withdraw_a_pending_offer(): void
    {
        $listing = $this->createListing($this->seller);
        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing);

        $offerId = $this->postOffer([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 48000.00,
        ])->assertStatus(201)->json('data.id');

        $this->postOfferAction('withdraw', $offerId, $this->seller)
            ->assertStatus(200);

        $this->assertSame('withdrawn', Offer::query()->sole()->status->value);
    }

    #[Test]
    public function a_non_party_cannot_view_an_offer(): void
    {
        $listing = $this->createListing($this->seller);
        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing);

        $offerId = $this->postOffer([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 48000.00,
        ])->assertStatus(201)->json('data.id');

        // A stranger who is neither buyer nor seller gets 404, never 403.
        $this->getOffer($offerId, $this->stranger)->assertStatus(404);
    }

    #[Test]
    public function the_buyer_can_view_a_pending_offer(): void
    {
        $listing = $this->createListing($this->seller);
        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing);

        $offerId = $this->postOffer([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 48000.00,
        ])->assertStatus(201)->json('data.id');

        $data = $this->getOffer($offerId, $this->buyer)
            ->assertStatus(200)
            ->json('data');

        $this->assertSame($offerId, $data['id']);
        $this->assertSame('pending', $data['status']);
        $this->assertSame('48000.00', $data['proposed_amount']);
        $this->assertSame($this->buyer->id, $data['buyer_id']);
    }

    #[Test]
    public function the_seller_can_view_their_own_offer(): void
    {
        $listing = $this->createListing($this->seller);
        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing);

        $offerId = $this->postOffer([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 48000.00,
        ])->assertStatus(201)->json('data.id');

        $this->getOffer($offerId, $this->seller)
            ->assertStatus(200)
            ->assertJsonPath('data.id', $offerId);
    }

    #[Test]
    public function the_offer_list_is_scoped_to_the_caller_and_filterable_by_counterpart(): void
    {
        $otherBuyer = User::factory()->create([
            'role' => UserRole::User,
            'name' => 'Maria Santos',
        ]);

        $listing = $this->createListing($this->seller);
        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing);

        $otherListing = $this->createListing($this->seller, [
            'livestock_type' => 'goat',
            'breed' => 'Boer',
        ]);
        $otherInquiry = $this->createInquiry($otherBuyer, $this->seller, $otherListing);

        $this->postOffer([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 48000.00,
        ])->assertStatus(201);

        $this->postOffer([
            'inquiry_id' => $otherInquiry->id,
            'listing_id' => $otherListing->id,
            'proposed_amount' => 12000.00,
        ])->assertStatus(201);

        // The buyer sees only the offer addressed to them.
        $buyerList = $this->getOffers(['counterpart_id' => $this->seller->id], $this->buyer)
            ->assertStatus(200)
            ->json('data.offers');

        $this->assertCount(1, $buyerList);
        $this->assertSame($inquiry->id, $buyerList[0]['inquiry_id']);

        // The seller sees both offers they made, and can narrow by counterpart.
        $sellerList = $this->getOffers([], $this->seller)
            ->assertStatus(200)
            ->json('data.offers');
        $this->assertCount(2, $sellerList);

        $sellerFiltered = $this->getOffers(
            ['counterpart_id' => $otherBuyer->id],
            $this->seller,
        )->assertStatus(200)->json('data.offers');
        $this->assertCount(1, $sellerFiltered);
        $this->assertSame($otherInquiry->id, $sellerFiltered[0]['inquiry_id']);

        // A seller who is party to neither offer sees an empty list.
        $this->getOffers([], $this->stranger)
            ->assertStatus(200)
            ->assertJsonCount(0, 'data.offers');
    }

    #[Test]
    public function the_transaction_created_by_acceptance_is_listed_for_both_parties(): void
    {
        $listing = $this->createListing($this->seller);
        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing);

        $offerId = $this->postOffer([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 48000.00,
        ])->assertStatus(201)->json('data.id');

        $transactionId = $this->postOfferAction('accept', $offerId, $this->buyer)
            ->assertStatus(200)
            ->json('data.transaction.id');

        $buyerList = $this->withHeader(
            'Authorization',
            'Bearer '.$this->mobileToken($this->buyer),
        )->getJson('/api/transactions?role=buyer')->assertStatus(200)
            ->json('data.transactions');

        $this->assertCount(1, $buyerList);
        $this->assertSame($transactionId, $buyerList[0]['id']);
        $this->assertSame('buyer', $buyerList[0]['role']);
        $this->assertSame('48000.00', $buyerList[0]['total_amount']);

        $sellerList = $this->withHeader(
            'Authorization',
            'Bearer '.$this->mobileToken($this->seller),
        )->getJson('/api/transactions?role=seller')->assertStatus(200)
            ->json('data.transactions');

        $this->assertCount(1, $sellerList);
        $this->assertSame($transactionId, $sellerList[0]['id']);
        $this->assertSame('seller', $sellerList[0]['role']);
        $this->assertSame('48000.00', $sellerList[0]['total_amount']);
    }

    #[Test]
    public function the_offer_list_refuses_ownership_filters(): void
    {
        $this->getOffers(['buyer_id' => $this->buyer->id], $this->seller)
            ->assertStatus(422)
            ->assertJsonValidationErrors(['buyer_id']);

        $this->getOffers(['seller_id' => $this->seller->id], $this->seller)
            ->assertStatus(422)
            ->assertJsonValidationErrors(['seller_id']);

        $this->getOffers(['user_id' => $this->buyer->id], $this->seller)
            ->assertStatus(422)
            ->assertJsonValidationErrors(['user_id']);
    }

    #[Test]
    public function a_seller_can_create_a_structured_offer_with_terms(): void
    {
        $listing = $this->createListing($this->seller);
        $preferred = now()->addDays(1)->toDateString();
        $proposed = now()->addDays(3)->toDateString();

        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing, [
            'payment_method' => 'gcash',
            'collection_method' => 'farm_pickup',
            'preferred_schedule' => $preferred,
        ]);

        $response = $this->postOffer([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 47000.00,
            'proposed_pickup_date' => $proposed,
            'payment_method' => 'cash',
            'collection_method' => 'buyer_arranged_transportation',
            'note' => 'Bring a helper.',
        ])->assertStatus(201)->json('data');

        $this->assertSame('47000.00', $response['proposed_amount']);
        $this->assertSame($proposed, $response['proposed_pickup_date']);
        $this->assertSame('cash', $response['payment_method']);
        $this->assertSame('buyer_arranged_transportation', $response['collection_method']);
        $this->assertSame('Bring a helper.', $response['note']);

        // The buyer's originals travel with the offer so the client can diff
        // without a second request.
        $this->assertSame('gcash', $response['original_terms']['payment_method']);
        $this->assertSame('farm_pickup', $response['original_terms']['collection_method']);
        $this->assertSame($preferred, $response['original_terms']['pickup_date']);

        $offer = Offer::query()->sole();
        $this->assertSame('cash', $offer->payment_method->value);
        $this->assertSame('buyer_arranged_transportation', $offer->collection_method->value);
        $this->assertSame($proposed, $offer->proposed_pickup_date->toDateString());
        $this->assertSame('Bring a helper.', $offer->note);
    }

    #[Test]
    public function an_unknown_term_value_is_rejected_with_422(): void
    {
        $listing = $this->createListing($this->seller);
        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing);

        $this->postOffer([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 47000.00,
            'payment_method' => 'bitcoin',
            'collection_method' => 'teleport',
        ])->assertStatus(422)
            ->assertJsonValidationErrors(['payment_method', 'collection_method']);

        $this->assertSame(0, Offer::query()->count());
    }

    #[Test]
    public function a_past_pickup_date_is_refused(): void
    {
        $listing = $this->createListing($this->seller);
        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing);

        $this->postOffer([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 47000.00,
            'proposed_pickup_date' => now()->subDay()->toDateString(),
        ])->assertStatus(422)
            ->assertJsonValidationErrors(['proposed_pickup_date']);

        $this->assertSame(0, Offer::query()->count());
    }

    #[Test]
    public function an_accepted_inquiry_can_never_receive_another_offer(): void
    {
        $listing = $this->createListing($this->seller);
        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing);

        $offerId = $this->postOffer([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 48000.00,
        ])->assertStatus(201)->json('data.id');

        $this->postOfferAction('accept', $offerId, $this->buyer)->assertStatus(200);

        $this->postOffer([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 45000.00,
        ])->assertStatus(409);

        $this->assertSame(1, Offer::query()->count());
        $this->assertSame(1, Transaction::query()->count());
    }

    #[Test]
    public function a_declined_offer_can_be_revised(): void
    {
        $listing = $this->createListing($this->seller);
        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing);

        $offerId = $this->postOffer([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 48000.00,
        ])->assertStatus(201)->json('data.id');

        $this->postOfferAction('decline', $offerId, $this->buyer)->assertStatus(200);

        $revised = $this->postOffer([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 46000.00,
        ])->assertStatus(201)->json('data');

        $this->assertSame('pending', $revised['status']);
        $this->assertSame('46000.00', $revised['proposed_amount']);
        $this->assertSame(2, Offer::query()->count());
    }

    #[Test]
    public function a_withdrawn_offer_can_be_revised(): void
    {
        $listing = $this->createListing($this->seller);
        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing);

        $offerId = $this->postOffer([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 48000.00,
        ])->assertStatus(201)->json('data.id');

        $this->postOfferAction('withdraw', $offerId, $this->seller)->assertStatus(200);

        $this->postOffer([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 47000.00,
        ])->assertStatus(201);
    }

    #[Test]
    public function accepting_a_structured_offer_snapshots_its_terms_on_the_transaction(): void
    {
        $listing = $this->createListing($this->seller);
        $pickup = now()->addDays(4)->toDateString();
        $inquiry = $this->createInquiry($this->buyer, $this->seller, $listing);

        $offerId = $this->postOffer([
            'inquiry_id' => $inquiry->id,
            'listing_id' => $listing->id,
            'proposed_amount' => 46000.00,
            'proposed_pickup_date' => $pickup,
            'payment_method' => 'maya',
            'collection_method' => 'farm_pickup',
            'note' => 'See you at 8am.',
        ])->assertStatus(201)->json('data.id');

        $response = $this->postOfferAction('accept', $offerId, $this->buyer)
            ->assertStatus(200)
            ->json('data');

        $transaction = Transaction::query()->sole();

        $this->assertSame($offerId, $transaction->offer_id);
        $this->assertSame('46000.00', $transaction->total_amount);
        $this->assertSame($pickup, $transaction->pickup_date->toDateString());
        $this->assertSame('maya', $transaction->payment_method);
        $this->assertSame('farm_pickup', $transaction->collection_method);

        $this->assertSame($pickup, $response['transaction']['terms']['pickup_date']);
        $this->assertSame('maya', $response['transaction']['terms']['payment_method']);
        $this->assertSame('farm_pickup', $response['transaction']['terms']['collection_method']);
        $this->assertSame($offerId, $response['transaction']['terms']['offer_id']);
    }
}
