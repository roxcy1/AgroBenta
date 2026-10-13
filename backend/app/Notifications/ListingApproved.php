<?php

namespace App\Notifications;

use App\Models\Listing;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;

/**
 * "Your listing was approved and is now live."
 *
 * Action `listing` with the listing's id lets the mobile client open the
 * seller's detail screen for that listing when the notification is tapped.
 */
class ListingApproved extends Notification
{
    use Queueable;

    public function __construct(
        public readonly Listing $listing,
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
        return [
            'type' => 'listing',
            'title' => 'Listing approved',
            'body' => "\"{$this->listing->title}\" is now live in the marketplace.",
            'action' => 'listing',
            'action_id' => $this->listing->getKey(),
        ];
    }
}