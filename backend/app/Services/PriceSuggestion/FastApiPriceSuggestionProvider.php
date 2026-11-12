<?php

namespace App\Services\PriceSuggestion;

use App\Contracts\PriceSuggestionProvider;
use App\Data\PriceSuggestionInput;
use App\Data\PriceSuggestionResult;
use App\Exceptions\PriceSuggestionRejected;
use App\Exceptions\PriceSuggestionUnavailable;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;
use Throwable;

/**
 * HTTP adapter for the private FastAPI prediction service.
 *
 * Laravel depends on the versioned HTTP contract only. This class never reads
 * CatBoost files, model names, or synthetic-data assumptions.
 */
class FastApiPriceSuggestionProvider implements PriceSuggestionProvider
{
    public function predict(PriceSuggestionInput $input): PriceSuggestionResult
    {
        $config = config('services.price_prediction', []);
        $baseUrl = rtrim((string) ($config['url'] ?? ''), '/');

        if ($baseUrl === '') {
            throw new PriceSuggestionUnavailable;
        }

        try {
            $response = Http::connectTimeout((int) ($config['connect_timeout'] ?? 2))
                ->timeout((int) ($config['timeout'] ?? 5))
                ->acceptJson()
                ->asJson()
                ->post($baseUrl.'/v1/predict', $input->toArray());
        } catch (ConnectionException $exception) {
            throw new PriceSuggestionUnavailable;
        } catch (Throwable $exception) {
            report($exception);

            throw new PriceSuggestionUnavailable;
        }

        $payload = $response->json();

        if ($response->status() === 422) {
            throw $this->rejectedFromPayload($payload);
        }

        if ($response->failed() || ! is_array($payload)) {
            throw new PriceSuggestionUnavailable;
        }

        $contractVersion = $payload['contract_version'] ?? null;
        $expectedVersion = (string) ($config['contract_version'] ?? '1.0');

        if (! is_string($contractVersion) || $contractVersion !== $expectedVersion) {
            throw new PriceSuggestionUnavailable(
                'The price suggestion service returned an incompatible contract version.'
            );
        }

        $status = $payload['status'] ?? null;
        $value = $payload['predicted_price_php'] ?? null;
        $warnings = $this->stringList($payload['warnings'] ?? []);
        $reasonCodes = $this->stringList($payload['reason_codes'] ?? []);
        $modelVersion = $payload['model_version'] ?? null;
        $modelSha256 = $payload['model_sha256'] ?? null;
        $provenance = $payload['provenance'] ?? null;

        if ($status === 'withheld' || $status === 'invalid') {
            throw new PriceSuggestionRejected(
                $status,
                $reasonCodes,
                $warnings,
            );
        }

        if (! in_array($status, ['ok', 'warning'], true)
            || ! is_numeric($value)
            || (float) $value <= 0
            || ! is_string($modelVersion)
            || ! is_string($modelSha256)
            || ! is_string($provenance)
        ) {
            throw new PriceSuggestionUnavailable(
                'The price suggestion service returned an invalid response.'
            );
        }

        return new PriceSuggestionResult(
            status: $status,
            value: (float) $value,
            warnings: $warnings,
            reasonCodes: $reasonCodes,
            modelVersion: $modelVersion,
            modelSha256: $modelSha256,
            provenance: $provenance,
            contractVersion: $contractVersion,
        );
    }

    private function rejectedFromPayload(mixed $payload): PriceSuggestionRejected
    {
        $status = is_array($payload) && in_array($payload['status'] ?? null, ['withheld', 'invalid'], true)
            ? $payload['status']
            : 'invalid';

        return new PriceSuggestionRejected(
            $status,
            is_array($payload) ? $this->stringList($payload['reason_codes'] ?? []) : [],
            is_array($payload) ? $this->stringList($payload['warnings'] ?? []) : [],
        );
    }

    /**
     * @return list<string>
     */
    private function stringList(mixed $value): array
    {
        if (! is_array($value)) {
            return [];
        }

        return array_values(array_filter($value, 'is_string'));
    }
}
