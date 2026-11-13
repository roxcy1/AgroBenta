<?php

namespace App\Http\Requests\SellerActivity;

use App\Repositories\SellerActivity\SellerActivityRepository;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Validator;

/**
 * Query for the seller activity feed.
 *
 * Two compatible shapes share one endpoint:
 *  - Seller Home sends `limit` (1–20) for its latest-five feed;
 *  - All Activities sends `page`, `per_page`, `category`, `from`, `to`.
 *
 * The seller scope is the token; ownership-shaped parameters are prohibited.
 */
class IndexSellerActivityRequest extends FormRequest
{
    public function authorize(): bool
    {
        // `auth:sanctum` + `ability:mobile` + the `seller` gate.
        return true;
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'limit' => ['nullable', 'integer', 'between:1,20'],
            'page' => ['nullable', 'integer', 'min:1'],
            'per_page' => ['nullable', 'integer', 'between:1,50'],
            'category' => ['nullable', 'string', Rule::in(array_keys(SellerActivityRepository::CATEGORIES))],
            'from' => ['nullable', 'date_format:Y-m-d'],
            'to' => ['nullable', 'date_format:Y-m-d', 'after_or_equal:from'],

            'seller_id' => ['prohibited'],
            'user_id' => ['prohibited'],
            'action' => ['prohibited'],
        ];
    }

    /**
     * @return array<int, callable>
     */
    public function after(): array
    {
        return [
            function (Validator $validator): void {
                if ($this->filled('limit') && ($this->filled('page') || $this->filled('per_page'))) {
                    $validator->errors()->add(
                        'limit',
                        'The limit parameter cannot be combined with page or per_page.',
                    );
                }
            },
        ];
    }

    public function limit(): int
    {
        return (int) ($this->validated('limit') ?? 5);
    }

    /**
     * The page size for the paginated shape. A legacy `limit` request is page 1
     * with that page size, so Seller Home keeps its exact contract.
     */
    public function perPage(): int
    {
        if ($this->filled('limit')) {
            return $this->limit();
        }

        // Legacy no-parameter call keeps the original five-row default; the All
        // Activities screen always sends `per_page` explicitly.
        return (int) ($this->validated('per_page') ?? 5);
    }

    public function pageNumber(): int
    {
        return $this->filled('limit') ? 1 : (int) ($this->validated('page') ?? 1);
    }
}
