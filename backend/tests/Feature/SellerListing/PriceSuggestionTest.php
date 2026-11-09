<?php

namespace Tests\Feature\SellerListing;

use App\Enums\ListingStatus;
use App\Enums\UserRole;
use App\Models\AiPriceEstimate;
use App\Models\Listing;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;
use Illuminate\Testing\TestResponse;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Seller price-suggestion endpoint against the private FastAPI contract.
 *
 * The provider is HTTP-faked here. These tests assert the Laravel boundary:
 * ownership, draft-only access, unit conversion, breed aliases, structured
 * errors, persistence, and that asking_price is never modified.
 */
class PriceSuggestionTest extends TestCase
{
    use RefreshDatabase;

    private User $seller;

    private User $otherSeller;

    private User $buyer;

    protected function setUp(): void
    {
        parent::setUp();

        config()->set('services.price_prediction.url', 'http://ml-service:8002');
        config()->set('services.price_prediction.connect_timeout', 2);
        config()->set('services.price_prediction.timeout', 5);
        config()->set('services.price_prediction.contract_version', '1.0');

        $this->seller = User::factory()->seller()->create([
            'role' => UserRole::User,
            'name' => 'Juan Dela Cruz',
        ]);
        $this->otherSeller = User::factory()->seller()->create([
            'role' => UserRole::User,
            'name' => 'Maria Santos',
        ]);
        $this->buyer = User::factory()->create([
            'role' => UserRole::User,
            'name' => 'Pedro Reyes',
        ]);
    }

    private function mobileToken(User $user): string
    {
        return $user->createToken('mobile', ['mobile'])->plainTextToken;
    }

    private function createListing(array $overrides = []): Listing
    {
        return Listing::create(array_merge([
            'seller_id' => $this->seller->id,
            'livestock_type' => 'cattle',
            'breed' => 'Brahman Cross',
            'age_value' => 2,
            'age_unit' => 'year',
            'gender' => 'male',
            'weight_value' => 1100,
            'weight_unit' => 'lb',
            'quantity' => 1,
            'asking_price' => 50000.00,
            'location' => 'Bukidnon',
            'health_status' => 'healthy',
            'vaccination' => 'up_to_date',
            'short_description' => 'Healthy bull',
            'additional_notes' => null,
            'photos' => [],
            'status' => ListingStatus::Draft,
        ], $overrides));
    }

    private function predict(Listing $listing, ?string $token = null): TestResponse
    {
        return $this->withHeader(
            'Authorization',
            'Bearer '.($token ?? $this->mobileToken($this->seller)),
        )->postJson('/api/seller/listings/'.$listing->id.'/price-suggestion');
    }

    /**
     * @return array<string, mixed>
     */
    private function successPayload(string $status = 'ok'): array
    {
        return [
            'contract_version' => '1.0',
            'status' => $status,
            'predicted_price_php' => 50000.55,
            'model_version' => 'v1',
            'model_sha256' => str_repeat('a', 64),
            'provenance' => 'synthetic',
            'warnings' => $status === 'warning' ? ['Input is outside the typical range.'] : [],
            'reason_codes' => $status === 'warning' ? ['outside_typical_weight'] : [],
        ];
    }

    #[Test]
    public function success_converts_units_normalizes_breed_and_persists(): void
    {
        $listing = $this->createListing();
        Http::fake([
            'http://ml-service:8002/v1/predict' => Http::response($this->successPayload(), 200),
        ]);

        $response = $this->predict($listing);

        $response->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.estimated_min', null)
            ->assertJsonPath('data.estimated_max', null)
            ->assertJsonPath('data.status', 'ok')
            ->assertJsonPath('data.provenance', 'synthetic')
            ->assertJsonPath('data.model_version', 'v1')
            ->assertJsonPath('data.warnings', []);

        $this->assertSame('50000.55', $response->json('data.estimated_value'));
        $this->assertEquals(24, $response->json('data.input_snapshot.age_months'));
        $this->assertEquals(498.9516, $response->json('data.input_snapshot.weight_kg'));
        $this->assertSame('brahman_cross', $response->json('data.input_snapshot.breed'));

        Http::assertSent(function ($request): bool {
            return $request->url() === 'http://ml-service:8002/v1/predict'
                && $request['breed'] === 'brahman_cross'
                && $request['sex'] === 'male'
                && (float) $request['age_months'] === 24.0
                && (float) $request['weight_kg'] === 498.9516;
        });

        $listing->refresh();
        $this->assertSame(ListingStatus::Draft, $listing->status);
        $this->assertSame('50000.00', $listing->asking_price);

        $estimate = AiPriceEstimate::firstOrFail();
        $this->assertSame('ok', $estimate->status);
        $this->assertSame('v1', $estimate->provider_metadata['model_version']);
        $this->assertSame('synthetic', $estimate->provider_metadata['provenance']);
        $this->assertSame($listing->id, $estimate->listing_id);
    }

    #[Test]
    public function quantity_is_not_sent_to_the_provider_and_the_estimate_stays_per_head(): void
    {
        $listing = $this->createListing(['quantity' => 12]);
        Http::fake([
            'http://ml-service:8002/v1/predict' => Http::response($this->successPayload(), 200),
        ]);

        $response = $this->predict($listing);

        $response->assertOk()
            ->assertJsonPath('data.estimated_value', '50000.55');

        Http::assertSent(function ($request): bool {
            $payload = $request->data();

            return $request->url() === 'http://ml-service:8002/v1/predict'
                && ! array_key_exists('quantity', $payload)
                && count($payload) === 5
                && array_keys($payload) === [
                    'livestock_type',
                    'breed',
                    'sex',
                    'age_months',
                    'weight_kg',
                ];
        });

        $listing->refresh();
        $this->assertSame('50000.00', $listing->asking_price);
        $this->assertSame(ListingStatus::Draft, $listing->status);
    }

    #[Test]
    public function warning_is_returned_and_persisted(): void
    {
        $listing = $this->createListing();
        Http::fake([
            'http://ml-service:8002/v1/predict' => Http::response(
                $this->successPayload('warning'),
                200,
            ),
        ]);

        $response = $this->predict($listing);

        $response->assertOk()
            ->assertJsonPath('data.status', 'warning')
            ->assertJsonPath('data.warnings.0', 'Input is outside the typical range.')
            ->assertJsonPath('data.reason_codes.0', 'outside_typical_weight');

        $this->assertDatabaseCount('ai_price_estimates', 1);
        $this->assertSame('warning', AiPriceEstimate::firstOrFail()->status);
    }

    #[Test]
    public function withheld_response_is_422_and_not_persisted(): void
    {
        $listing = $this->createListing();
        Http::fake([
            'http://ml-service:8002/v1/predict' => Http::response([
                'contract_version' => '1.0',
                'status' => 'withheld',
                'predicted_price_php' => null,
                'model_version' => 'v1',
                'model_sha256' => str_repeat('a', 64),
                'provenance' => 'synthetic',
                'warnings' => ['Outside supported envelope.'],
                'reason_codes' => ['outside_supported_weight'],
            ], 422),
        ]);

        $response = $this->predict($listing);

        $response->assertStatus(422)
            ->assertJsonPath('success', false)
            ->assertJsonPath('status', 'withheld')
            ->assertJsonPath('reason_codes.0', 'outside_supported_weight');
        $this->assertDatabaseCount('ai_price_estimates', 0);
        $this->assertSame('50000.00', $listing->fresh()->asking_price);
    }

    #[Test]
    public function missing_required_listing_inputs_are_422_without_provider_call(): void
    {
        $listing = $this->createListing(['age_value' => null, 'age_unit' => null]);
        Http::fake();

        $response = $this->predict($listing);

        $response->assertStatus(422)
            ->assertJsonPath('success', false)
            ->assertJsonPath('status', 'invalid')
            ->assertJsonPath('reason_codes.0', 'missing_age');
        Http::assertNothingSent();
        $this->assertDatabaseCount('ai_price_estimates', 0);
    }

    #[Test]
    public function unsupported_breed_is_422_without_provider_call(): void
    {
        $listing = $this->createListing(['breed' => 'Angus']);
        Http::fake();

        $response = $this->predict($listing);

        $response->assertStatus(422)
            ->assertJsonPath('status', 'invalid')
            ->assertJsonPath('reason_codes.0', 'unsupported_breed');
        Http::assertNothingSent();
    }

    #[Test]
    public function day_and_kg_conversion_are_sent_canonically(): void
    {
        $listing = $this->createListing([
            'age_value' => 30,
            'age_unit' => 'day',
            'weight_value' => 40,
            'weight_unit' => 'kg',
            'breed' => 'Boer',
            'livestock_type' => 'goat',
        ]);
        Http::fake([
            'http://ml-service:8002/v1/predict' => Http::response($this->successPayload(), 200),
        ]);

        $this->predict($listing)->assertOk();

        Http::assertSent(function ($request): bool {
            return abs($request['age_months'] - 0.985626) < 0.000001
                && (float) $request['weight_kg'] === 40.0
                && $request['breed'] === 'boer'
                && $request['livestock_type'] === 'goat';
        });
    }

    #[Test]
    public function young_chicken_inputs_are_sent_canonically(): void
    {
        $listing = $this->createListing([
            'livestock_type' => 'chicken',
            'breed' => 'Broiler',
            'age_value' => 15,
            'age_unit' => 'day',
            'weight_value' => 0.5,
            'weight_unit' => 'kg',
        ]);
        Http::fake([
            'http://ml-service:8002/v1/predict' => Http::response($this->successPayload(), 200),
        ]);

        $this->predict($listing)->assertOk();

        Http::assertSent(function ($request): bool {
            return $request['livestock_type'] === 'chicken'
                && $request['breed'] === 'broiler'
                && abs($request['age_months'] - 0.492813) < 0.000001
                && (float) $request['weight_kg'] === 0.5;
        });
    }

    #[Test]
    public function another_sellers_listing_is_404(): void
    {
        $listing = $this->createListing();
        Http::fake();

        $response = $this->predict($listing, $this->mobileToken($this->otherSeller));

        $response->assertStatus(404);
        Http::assertNothingSent();
        $this->assertDatabaseCount('ai_price_estimates', 0);
    }

    #[Test]
    public function buyer_is_forbidden(): void
    {
        $listing = $this->createListing();
        Http::fake();

        $response = $this->predict($listing, $this->mobileToken($this->buyer));

        $response->assertStatus(403);
        Http::assertNothingSent();
    }

    #[Test]
    public function unauthenticated_request_is_401(): void
    {
        $listing = $this->createListing();
        Http::fake();

        $this->postJson('/api/seller/listings/'.$listing->id.'/price-suggestion')
            ->assertStatus(401);
        Http::assertNothingSent();
    }

    #[Test]
    public function active_listing_is_422(): void
    {
        $listing = $this->createListing(['status' => ListingStatus::Active]);
        Http::fake();

        $response = $this->predict($listing);

        $response->assertStatus(422)
            ->assertJsonPath('status', 'invalid')
            ->assertJsonPath('reason_codes.0', 'listing_not_draft');
        Http::assertNothingSent();
    }

    #[Test]
    public function provider_unavailable_is_safe_503(): void
    {
        $listing = $this->createListing();
        Http::fake([
            'http://ml-service:8002/v1/predict' => Http::response([], 503),
        ]);

        $response = $this->predict($listing);

        $response->assertStatus(503)
            ->assertJsonPath('success', false)
            ->assertJsonPath('status', 'unavailable')
            ->assertJsonPath('reason_codes.0', 'provider_unavailable');
        $this->assertDatabaseCount('ai_price_estimates', 0);
    }

    #[Test]
    public function provider_timeout_is_safe_503(): void
    {
        $listing = $this->createListing();
        Http::fake(function (): void {
            throw new ConnectionException('timeout');
        });

        $response = $this->predict($listing);

        $response->assertStatus(503)
            ->assertJsonPath('reason_codes.0', 'provider_unavailable');
        $this->assertDatabaseCount('ai_price_estimates', 0);
    }

    #[Test]
    public function malformed_or_incompatible_provider_response_is_503(): void
    {
        $listing = $this->createListing();
        Http::fake([
            'http://ml-service:8002/v1/predict' => Http::response([
                'status' => 'ok',
                'predicted_price_php' => 50000,
                'model_version' => 'v1',
                'model_sha256' => str_repeat('a', 64),
                'provenance' => 'synthetic',
            ], 200),
        ]);

        $response = $this->predict($listing);

        $response->assertStatus(503)
            ->assertJsonPath('status', 'unavailable');
        $this->assertDatabaseCount('ai_price_estimates', 0);
    }
}
