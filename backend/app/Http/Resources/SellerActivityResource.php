<?php

namespace App\Http\Resources;

use App\Enums\ActivityAction;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;
use Illuminate\Support\Arr;

/**
 * One seller-relevant activity event.
 *
 * Only safe, navigation-oriented fields leave the server: the event identity,
 * its human label, description, timestamp and the ids a client may use to open
 * an existing screen. The raw metadata bag stays server-side.
 */
class SellerActivityResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $metadata = is_array($this->metadata) ? $this->metadata : [];
        $context = is_array($metadata['context'] ?? null)
            ? $metadata['context']
            : [];
        $action = ActivityAction::tryFrom((string) $this->action);

        return [
            'id' => $this->id,
            'action' => $this->action,
            'label' => $action?->label() ?? $this->action,
            'description' => $this->description,
            'created_at' => $this->created_at?->toISOString(),
            'target_type' => $metadata['target_type'] ?? null,
            'target_id' => isset($metadata['target_id']) ? (int) $metadata['target_id'] : null,
            // Only ids a client already has a screen for. `admin_note`,
            // `changes` and actor details never travel here.
            // Always a JSON object: an empty context must serialise as `{}`,
            // never `[]` — the mobile parser (and any JSON-schema consumer)
            // reads an object here, so an empty array is a contract break.
            'context' => (object) array_map(
                static fn (mixed $value): ?int => $value === null ? null : (int) $value,
                Arr::only($context, [
                    'listing_id',
                    'buyer_id',
                    'offer_id',
                    'transaction_id',
                    'inquiry_id',
                ]),
            ),
        ];
    }
}
