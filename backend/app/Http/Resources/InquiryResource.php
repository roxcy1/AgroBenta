<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * The administrator-facing shape of an inquiry.
 *
 * Carries the parties' emails because the Admin Web reviews inquiries and needs
 * to identify the accounts. It is deliberately not reused for mobile: a mobile
 * projection would be a separate `Mobile*` resource, and would omit email.
 */
class InquiryResource extends JsonResource
{
    /**
     * Transform the resource into an array.
     *
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'buyer' => $this->buyer ? [
                'id' => $this->buyer->id,
                'name' => $this->buyer->name,
                'email' => $this->buyer->email,
            ] : null,
            'seller' => $this->seller ? [
                'id' => $this->seller->id,
                'name' => $this->seller->name,
                'email' => $this->seller->email,
            ] : null,
            'listing' => $this->listing ? [
                'id' => $this->listing->id,
                'livestock_type' => $this->listing->livestock_type,
                'breed' => $this->listing->breed,
            ] : null,
            'subject' => $this->subject,
            'message' => $this->message,
            'purchase_interest' => $this->purchase_interest,
            'transaction_method' => $this->transaction_method?->value,
            'delivery_method' => $this->delivery_method,
            'delivery_fee' => $this->delivery_fee,
            'contact_method' => $this->contact_method?->value,
            'preferred_schedule' => $this->preferred_schedule?->toDateString(),
            'status' => $this->status?->value,
            'created_at' => $this->created_at?->toISOString(),
            'updated_at' => $this->updated_at?->toISOString(),
        ];
    }
}
