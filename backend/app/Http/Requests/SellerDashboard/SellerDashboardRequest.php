<?php

namespace App\Http\Requests\SellerDashboard;

use Illuminate\Foundation\Http\FormRequest;

/**
 * The seller dashboard takes no client-selected scope.
 *
 * The seller is always the token's user. Ownership-shaped query parameters are
 * prohibited rather than ignored, so a caller cannot believe it has widened or
 * redirected the summary.
 */
class SellerDashboardRequest extends FormRequest
{
    public function authorize(): bool
    {
        // Authentication and the seller capability gate belong to the route.
        return true;
    }

    /**
     * @return array<string, list<string>>
     */
    public function rules(): array
    {
        return [
            'buyer_id' => ['prohibited'],
            'seller_id' => ['prohibited'],
            'user_id' => ['prohibited'],
            'role' => ['prohibited'],
            'status' => ['prohibited'],
        ];
    }
}
