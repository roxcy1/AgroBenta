<?php

namespace App\Http\Requests\Admin;

use Illuminate\Foundation\Http\FormRequest;

/**
 * Evidence-backed reconciliation of a listing whose historical inventory is
 * uncertain. The authenticated administrator is the only source of the audit
 * actor; transaction ids are scoped and verified in the service.
 */
class ReconcileListingInventoryRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, list<string>>
     */
    public function rules(): array
    {
        return [
            // Count of physical animals that are currently available to new
            // buyers, excluding the pending transactions allocated below.
            'verified_physical_quantity' => ['required', 'integer', 'min:0', 'max:4294967295'],
            'verified_externally_sold_quantity' => ['required', 'integer', 'min:0', 'max:4294967295'],
            'accounted_transaction_ids' => ['required', 'array'],
            'accounted_transaction_ids.*' => [
                'required', 'integer', 'distinct', 'exists:transactions,id',
            ],
            'reason' => ['required', 'string', 'min:8', 'max:1000'],
            'evidence' => ['nullable', 'string', 'max:5000'],

            'listing_id' => ['prohibited'],
            'admin_id' => ['prohibited'],
            'status' => ['prohibited'],
            'quantity' => ['prohibited'],
            'total_quantity' => ['prohibited'],
        ];
    }
}
