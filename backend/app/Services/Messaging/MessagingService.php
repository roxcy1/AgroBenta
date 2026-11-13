<?php

namespace App\Services\Messaging;

use App\Events\MessageSent;
use App\Models\Inquiry;
use App\Models\Message;
use App\Models\User;
use App\Notifications\NewInquiry;
use App\Repositories\Messaging\MessageRepository;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Support\Collection;

/**
 * The business logic for messaging.
 *
 * ## What this service owns that the repository does not
 *
 * Two things:
 *
 *  1. **The "first message in a thread" rule** — a notification fires only the
 *     first time a buyer writes to a seller about a listing. Subsequent
 *     messages in the same thread are silent. This is the behaviour the
 *     prototype shows ("New Inquiry" appears once, not once per message).
 *
 *  2. **The notification dispatch itself** — the repository never sends
 *     notifications; that is the service's job.
 *
 * Everything else — reads, pagination, marking read — is a pass-through to
 * the repository, and exists here so the controller has a single dependency.
 *
 * ## Why sending a message is not wrapped in a DB transaction
 *
 * The write to `messages` and the write to `notifications` are both single
 * INSERTs, and the second is conditional (only the first message of a thread).
 * Wrapping them in a transaction would buy nothing: a failure between them
 * would leave a message with no notification, which is a degraded but valid
 * state — the next message in the thread still fires nothing, so the
 * notification is silently lost rather than duplicated. That is acceptable for
 * an inquiry notification; it would not be acceptable for a payment.
 */
class MessagingService
{
    public function __construct(
        private readonly MessageRepository $messages,
    ) {
        //
    }

    /**
     * The conversation list for one user.
     *
     * @return Collection<int, object>
     */
    public function conversationsFor(User $user): Collection
    {
        return $this->messages->conversationsFor($user->id);
    }

    /**
     * One thread, paginated.
     */
    public function threadBetween(
        User $user,
        int $counterpartId,
        ?int $listingId = null,
        int $perPage = 30,
    ): LengthAwarePaginator {
        $page = $this->messages->threadBetween(
            $user->id,
            $counterpartId,
            $listingId,
            $perPage,
        );

        $this->attachInquiryPreviews($page, $user->id, $counterpartId);

        return $page;
    }

    /**
     * Attach one structured inquiry card to the message that opened it.
     *
     * The initial inquiry message is written in the same transaction as the
     * inquiry itself, so the earliest message on that listing from the
     * inquiry's buyer is its opener. Attaching at most one preview per inquiry
     * is what keeps a thread with several listings free of duplicate cards.
     */
    private function attachInquiryPreviews(
        LengthAwarePaginator $page,
        int $userId,
        int $counterpartId,
    ): void {
        $inquiries = $this->messages->inquiriesForPair($userId, $counterpartId);

        if ($inquiries->isEmpty()) {
            return;
        }

        /** @var Collection<int, Message> $oldestFirst */
        $oldestFirst = $page->getCollection()->reverse()->values();

        foreach ($inquiries as $inquiry) {
            foreach ($oldestFirst as $message) {
                if ((int) $message->listing_id !== (int) $inquiry->listing_id) {
                    continue;
                }

                if ((int) $message->sender_id !== (int) $inquiry->buyer_id) {
                    continue;
                }

                if ($message->created_at === null || $message->created_at->lt($inquiry->created_at)) {
                    continue;
                }

                if ($message->getAttribute('inquiry_preview') !== null) {
                    continue;
                }

                $message->setAttribute('inquiry_preview', $this->inquiryPreview($inquiry));
                break;
            }
        }
    }

    /**
     * The compact inquiry payload the chat renders as a card.
     *
     * @return array<string, mixed>
     */
    private function inquiryPreview(Inquiry $inquiry): array
    {
        $listing = $inquiry->listing;
        $photos = $listing?->photos;
        $photo = is_array($photos) && $photos !== [] ? (string) reset($photos) : null;

        return [
            'id' => (int) $inquiry->id,
            'listing' => $listing === null ? null : [
                'id' => (int) $listing->id,
                'title' => trim(($listing->livestock_type ?? '').' '.($listing->breed ?? '')),
                'asking_price' => $listing->asking_price,
                'photo_url' => $photo,
            ],
            'payment_method' => $inquiry->payment_method?->value,
            'collection_method' => $inquiry->collection_method?->value,
            'preferred_schedule' => $inquiry->preferred_schedule?->toDateString(),
            'message' => $inquiry->message,
        ];
    }

    /**
     * Sends a message from `$sender` to `$receiver`.
     *
     * When `$notify` is `true` (the inquiry flow), a `NewInquiry` notification
     * is always dispatched — even when reusing an existing buyer–seller
     * conversation — so every new inquiry alerts the seller. Duplicate
     * requests are stopped at the inquiry level (unique buyer+listing index),
     * so this cannot produce duplicate notifications.
     *
     * When `$notify` is `null` (the regular chat flow), the notification fires
     * only on the first message between the sender and receiver about this
     * listing, preserving existing behaviour.
     */
    public function sendMessage(
        User $sender,
        User $receiver,
        string $body,
        ?int $listingId = null,
        ?bool $notify = null,
    ): Message {
        $isFirstInThread = $this->messages
            ->threadBetween($sender->id, $receiver->id, $listingId, 1)
            ->total() === 0;

        $message = Message::create([
            'sender_id' => $sender->id,
            'receiver_id' => $receiver->id,
            'listing_id' => $listingId,
            'body' => $body,
        ]);

        $shouldNotify = $notify ?? $isFirstInThread;
        if ($shouldNotify) {
            $receiver->notify(new NewInquiry($sender, $message, $listingId));
        }

        // Notify the receiver's connected client. Queued and dispatched after
        // commit (see MessageSent), so a broadcast failure cannot fail the send
        // and a rolled-back transaction cannot broadcast a phantom message.
        MessageSent::dispatch($message);

        return $message->fresh(['sender:id,name,avatar_url', 'receiver:id,name,avatar_url']);
    }

    /**
     * Marks the entire thread with a counterpart as read.
     *
     * @return int The number of messages that flipped from unread to read.
     */
    public function markThreadRead(
        User $user,
        int $counterpartId,
        ?int $listingId = null,
    ): int {
        return $this->messages->markThreadRead(
            $user->id,
            $counterpartId,
            $listingId,
        );
    }

    /**
     * Marks a single message as read.
     *
     * Returns null when the message does not exist or is not addressed to the
     * caller — the controller turns that into a 404.
     */
    public function markOneRead(User $user, int $messageId): ?Message
    {
        return $this->messages->markOneRead($user->id, $messageId);
    }
}
