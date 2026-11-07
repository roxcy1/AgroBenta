<?php

namespace App\Http\Controllers\Api\SellerListing;

use App\Exceptions\PriceSuggestionRejected;
use App\Exceptions\PriceSuggestionUnavailable;
use App\Http\Controllers\Controller;
use App\Http\Requests\SellerListing\SellerListingActionRequest;
use App\Http\Resources\AiPriceEstimateResource;
use App\Services\PriceSuggestion\PriceSuggestionService;
use App\Services\SellerListing\SellerListingService;
use Illuminate\Http\JsonResponse;
use Throwable;

/**
 * Request a point price suggestion for one of the seller's own draft listings.
 *
 * The endpoint is optional decision support. It never writes asking_price or
 * changes the listing lifecycle.
 */
class PriceSuggestionController extends Controller
{
    public function __construct(
        private readonly SellerListingService $listings,
        private readonly PriceSuggestionService $suggestions,
    ) {
        //
    }

    public function store(SellerListingActionRequest $request, string $listing): JsonResponse
    {
        $owned = $this->listings->findOwnedForSeller(
            (int) $listing,
            $request->user(),
        );

        if ($owned === null) {
            abort(404, 'Listing not found.');
        }

        try {
            $estimate = $this->suggestions->generate($owned);
        } catch (PriceSuggestionRejected $exception) {
            return response()->json([
                'success' => false,
                'message' => $exception->getMessage(),
                'status' => $exception->status,
                'warnings' => $exception->warnings,
                'reason_codes' => $exception->reasonCodes,
            ], 422);
        } catch (PriceSuggestionUnavailable $exception) {
            return response()->json([
                'success' => false,
                'message' => 'The price suggestion service is unavailable.',
                'status' => 'unavailable',
                'warnings' => [],
                'reason_codes' => ['provider_unavailable'],
            ], 503);
        } catch (Throwable $exception) {
            report($exception);

            return response()->json([
                'success' => false,
                'message' => 'The price suggestion could not be generated.',
                'status' => 'error',
                'warnings' => [],
                'reason_codes' => ['internal_error'],
            ], 500);
        }

        return response()->json([
            'success' => true,
            'message' => 'Price suggestion generated.',
            'data' => new AiPriceEstimateResource($estimate),
        ], 200);
    }
}
