<?php

namespace App\Notifications;

use App\Models\SellerVerification;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;

/**
 * "Your seller verification was approved."
 *
 * ## Why this is database-only
 *
 * Laravel's `Notification` supports many channels — database, mail, SMS,
 * broadcast. AgroBenta's mobile client reads notifications from
 * `GET /api/notifications`, so the `database` channel is the only one that
 * actually delivers anything today. Adding `mail` would require a working SMTP
 * setup and a mail template; adding `broadcast` would require a WebSocket
 * server. Neither exists, and a notification that pretends to send an email it
 * cannot deliver is worse than one that only writes to the database.
 *
 * When mail is configured (D-XX), the `via()` method can return
 * `['database', 'mail']` and add a `toMail()` method. Nothing else changes.
 *
 * ## Why the payload shape
 *
 * The mobile client renders a notification from `data`, so the keys are chosen
 * to match what the screen needs:
 *
 *  - `title`    — the headline, e.g. "Seller verification approved"
 *  - `body`     — the one-line summary, e.g. "You can now list livestock for sale."
 *  - `type`     — the machine-readable category, e.g. "seller_verification"
 *  - `action`   — optional. Which screen to open on tap:
 *                 "verification", "listing", "transaction", null.
 *  - `action_id` — optional. The id the target screen needs (listing id, etc.)
 *
 * The client never parses `type` to decide what to render; it uses `type` only
 * for the filter chips ("All", "Transactions", ...) and `action` for
 * navigation. Everything visual comes from `title`, `body` and a fixed icon.
 */
class SellerVerificationApproved extends Notification
{
    use Queueable;

    /**
     * @param  SellerVerification  $verification  The record the admin acted on.
     *                                            Carries the applicant's id and the review note.
     */
    public function __construct(
        public readonly SellerVerification $verification,
    ) {
    }

    /**
     * The delivery channels.
     *
     * @return array<int, string>
     */
    public function via(object $notifiable): array
    {
        return ['database'];
    }

    /**
     * The payload stored in `notifications.data`.
     *
     * @return array<string, mixed>
     */
    public function toArray(object $notifiable): array
    {
        $note = $this->verification->admin_note;

        return [
            'type' => 'seller_verification',
            'title' => 'Seller verification approved',
            'body' => $note !== null && $note !== ''
                ? "You can now list livestock for sale. Note: {$note}"
                : 'You can now list livestock for sale.',
            'action' => 'verification',
            'action_id' => $this->verification->getKey(),
        ];
    }
}