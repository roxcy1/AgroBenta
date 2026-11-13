<?php

namespace App\Jobs;

use App\Services\Push\PushNotificationService;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Contracts\Queue\ShouldQueueAfterCommit;
use Illuminate\Foundation\Queue\Queueable;

/**
 * Push one stored notification to the recipient's phones.
 *
 * Queued after commit, like the Reverb broadcasts, so FCM being slow or down
 * never delays or fails the request that created the notification, and a
 * rolled-back transaction never pushes. One attempt only: a retry would
 * resend to the phones that already received it.
 */
class SendPushNotification implements ShouldQueue, ShouldQueueAfterCommit
{
    use Queueable;

    public int $tries = 1;

    /**
     * @param  array<string, string>  $data
     */
    public function __construct(
        public readonly int $userId,
        public readonly string $title,
        public readonly array $data,
    ) {}

    public function handle(PushNotificationService $push): void
    {
        $push->sendToUser($this->userId, $this->title, $this->data);
    }
}
