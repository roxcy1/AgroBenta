<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * The mobile-safe projection of a seller verification.
 *
 * The administrator-facing `SellerVerificationResource` is deliberately not
 * reused, trimmed or extended here. It embeds `seller.email` and a `reviewer`
 * object, and a verification record is the account's own data being read back
 * to the account that submitted it — so the leak it risks is not a stranger's
 * email but a mobile client being handed an administrator's identity (contract
 * §8.1: "a mobile response must never carry administrator-only data: reviewer
 * identities"). Trimming a shared resource per client is how that field gets
 * re-added for the Admin Web and silently re-exposed (F-08).
 *
 * What is included, and why each is safe:
 *
 *  - `id`, and the four business fields the client itself just submitted. The
 *    client is echoing its own input back.
 *  - `status`, so the app can render pending, rejected, or approved.
 *  - `admin_note`, explicitly required by contract §5.3 so a rejected user can
 *    be told *why* without inventing a reason. It is written for the user, so it
 *    is not administrator-internal despite the column name.
 *  - `submitted_at` / `reviewed_at`, so "awaiting review" can say how long, and a
 *    rejection can show when the decision was made.
 *
 * What is absent, and must stay absent:
 *
 *  - `seller` entirely. The viewer is always `$me`, so a seller block would be
 *    the caller's own name and email handed back to them for no benefit.
 *  - `reviewer`. Administrator identity, forbidden above.
 *  - `user_id`. The caller's own id, and echoing it invites a client to start
 *    treating it as a request field.
 *
 * `created_at` / `updated_at` are omitted for the same reason as `user_id`: they
 * are database bookkeeping, not something the four business states need. The
 * decision timestamps are the ones a person can act on.
 */
class MobileSellerVerificationResource extends JsonResource
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
            'business_name' => $this->business_name,
            'business_location' => $this->business_location,
            'business_description' => $this->business_description,
            'id_document_ref' => $this->id_document_ref,
            'status' => $this->status?->value,
            'admin_note' => $this->admin_note,
            'submitted_at' => $this->submitted_at?->toISOString(),
            'reviewed_at' => $this->reviewed_at?->toISOString(),
        ];
    }
}
