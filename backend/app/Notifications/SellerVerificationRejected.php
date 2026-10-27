<?php

namespace App\Notifications;

use App\Models\SellerVerification;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;

/**
 * "Your seller verification was rejected."
 *
 * The admin note is important here: the applicant needs to know *what* to fix
 * before resubmitting, and the note is the only place the reviewer's wording
 * lives. It is included in the body when present, and the body falls back to a
 * generic message when the reviewer left it empty.
 */
class SellerVerificationRejected extends Notification
{
    use Queueable;

    public function __construct(
        public readonly SellerVerification $verification,
    ) {
    }

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
            'title' => 'Seller verification not approved',
            'body' => $note !== null && $note !== ''
                ? "Reason: {$note}"
                : 'Open the app to review the decision and resubmit.',
            'action' => 'verification',
            'action_id' => $this->verification->getKey(),
        ];
    }
}