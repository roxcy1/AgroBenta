<?php

namespace App\Notifications;

use App\Models\Message;
use App\Models\User;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;

/**
 * "You have a new inquiry about <listing>."
 *
 * Fired by `MessagingService::sendMessage` the first time a buyer writes to a
 * seller about a given listing. Replies in the same thread are silent — the
 * receiver already knows the conversation exists.
 *
 * ## Why the payload does not carry the message body
 *
 * The notification preview shows the sender's name and the listing, not the
 * message. Two reasons:
 *
 *  1. Pushing full message text into `notifications.data` duplicates it, and
 *     the two copies can drift if the message is edited or deleted.
 *  2. The mobile thread screen fetches the actual messages anyway, so the
 *     notification only needs to be a *pointer* — tap → open this thread.
 *
 * The `action` is `inquiry` and `action_id` is the counterpart's user id, so
 * the client knows which thread to open when the notification is tapped.
 */
class NewInquiry extends Notification
{
    use Queueable;

    public function __construct(
        public readonly User $sender,
        public readonly Message $message,
        public readonly ?int $listingId,
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
        $listing = $this->message->listing;

        $body = $listing !== null
            ? "{$this->sender->name} is interested in your {$listing->livestock_type} listing."
            : "{$this->sender->name} sent you a message.";

        return [
            'type' => 'inquiry',
            'title' => 'New inquiry',
            'body' => $body,
            'action' => 'inquiry',
            'action_id' => $this->sender->id,
        ];
    }
}