<?php

namespace App\Notifications;

use App\Models\Listing;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;

/**
 * "Your listing was rejected."
 *
 * The admin note is the only place the reviewer's reason lives, so it is
 * surfaced prominently. A rejection with no reason is a worse experience than
 * no notification at all — but if the reviewer left it blank, the client still
 * gets a message it can show.
 */
class ListingRejected extends Notification
{
    use Queueable;

    public function __construct(
        public readonly Listing $listing,
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
        $note = $this->listing->admin_note;
        $label = $this->listing->displayLabel();

        return [
            'type' => 'listing',
            'title' => 'Listing not approved',
            'body' => $note !== null && $note !== ''
                ? "Reason: {$note}"
                : "\"{$label}\" was not approved.",
            'action' => 'listing',
            'action_id' => $this->listing->getKey(),
        ];
    }
}
