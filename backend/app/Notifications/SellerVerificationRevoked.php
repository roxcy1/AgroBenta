<?php

namespace App\Notifications;

use App\Models\SellerVerification;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;

/**
 * "Your seller verification was revoked."
 *
 * A revocation is different from a rejection: the applicant was previously an
 * approved seller, so the message must explain that seller capability has ended
 * and that live and pending listings were withdrawn. The required admin note is
 * the only place the reviewer's reason lives, so it is included when present.
 *
 * Database-only, matching the approval and rejection notifications: the mobile
 * client reads notifications from `GET /api/notifications`, and the existing
 * `seller_verification` type is what refreshes the verification screen.
 */
class SellerVerificationRevoked extends Notification
{
    use Queueable;

    public function __construct(
        public readonly SellerVerification $verification,
    ) {}

    /**
     * @return array<int, string>
     */
    public function via(object $notifiable): array
    {
        return ['database'];
    }

    /**
     * @return array<string, mixed>
     */
    public function toArray(object $notifiable): array
    {
        $note = $this->verification->admin_note;

        return [
            'type' => 'seller_verification',
            'title' => 'Seller verification revoked',
            'body' => $note !== null && $note !== ''
                ? "Your seller capability has been revoked and your active and pending listings were withdrawn. Reason: {$note}"
                : 'Your seller capability has been revoked and your active and pending listings were withdrawn.',
            'action' => 'verification',
            'action_id' => $this->verification->getKey(),
        ];
    }
}
