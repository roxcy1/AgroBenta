<?php

namespace App\Repositories\Messaging;

use App\Models\Message;
use App\Models\User;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Support\Collection;

/**
 * Every database query the messaging feature makes.
 *
 * The repository exists so the service never touches Eloquent directly. That
 * means: no `Message::query()` calls scattered through business logic, and one
 * place to change if a query needs an index or a different eager-load. The
 * service still owns transaction boundaries and notification dispatch — it
 * just asks the repository for data.
 *
 * ## Why some methods take a user id and some a User
 *
 * Anything that filters *by the authenticated caller* takes an int id, because
 * the caller is a scalar in the request and turning it into a User would mean
 * loading a row the feature already knows. Anything that needs the caller's
 * relation (the counterpart's name, avatar) takes a User and uses Eloquent's
 * relation methods on it.
 */
class MessageRepository
{
    /**
     * The thread between two users, optionally narrowed to one listing.
     *
     * Newest first — the mobile client renders a chat top-down and inverts the
     * list, the same way `MarketplaceRepository` returns newest-first. Taking
     * `listing_id` as a nullable argument keeps "the general thread" and "the
     * thread about this listing" a single call.
     */
    public function threadBetween(
        int $userId,
        int $counterpartId,
        ?int $listingId = null,
        int $perPage = 30,
    ): LengthAwarePaginator {
        return Message::query()
            ->betweenUsers($userId, $counterpartId)
            ->when(
                $listingId !== null,
                fn ($q) => $q->where('listing_id', $listingId),
            )
            ->with(['sender:id,name,avatar_url', 'receiver:id,name,avatar_url'])
            ->orderByDesc('created_at')
            ->paginate($perPage);
    }

    /**
     * The conversation list for one user.
     *
     * This is the trickiest query in the feature. A conversation is not a row
     * in the database — it is derived from the set of messages that touch the
     * caller. "Show me every thread I'm in, with the newest message in each
     * and how many unread messages are waiting" is a GROUP BY that has to
     * work for both directions of every pair.
     *
     * ## Why grouping happens in PHP and not in SQL
     *
     * MySQL 8 handles `CASE WHEN sender_id = :me THEN receiver_id ELSE sender_id`
     * in a GROUP BY, but doing it there defeats the eager-loads on `sender`,
     * `receiver` and `listing` (the resulting rows are not Message models).
     * Grouping 500 messages in memory is a few milliseconds and keeps this
     * method readable, which matters more than micro-optimising a list screen.
     *
     * ## Why the map callback receives an array
     *
     * `Collection::groupBy()` returns a Collection whose *values* are plain PHP
     * arrays, not sub-collections. So the callback signature must say
     * `array $messages`, and it must wrap the array back into a Collection
     * (`collect(...)`) before handing it to `buildConversation`, which uses
     * Collection methods (`first()`, `where()`, `count()`).
     *
     * @return Collection<int, array<string, mixed>>
     */
    public function conversationsFor(int $userId): Collection
    {
        return Message::query()
            ->select([
                'id',
                'sender_id',
                'receiver_id',
                'listing_id',
                'body',
                'read_at',
                'created_at',
            ])
            ->where(function ($q) use ($userId): void {
                $q->where('sender_id', $userId)->orWhere('receiver_id', $userId);
            })
            ->with([
                'sender:id,name,avatar_url',
                'receiver:id,name,avatar_url',
                'listing:id,livestock_type,breed',
            ])
            ->orderByDesc('created_at')
            ->get()
            ->groupBy(fn (Message $m): string => $this->conversationKey($userId, $m))
                        ->map(fn (Collection $messages): array => $this->buildConversation($userId, $messages))
            ->values();
    }

    /**
     * Marks every unread message from a counterpart as read, optionally
     * narrowed to one listing.
     *
     * @return int The number of rows updated.
     */
    public function markThreadRead(int $userId, int $counterpartId, ?int $listingId = null): int
    {
        return Message::query()
            ->where('receiver_id', $userId)
            ->where('sender_id', $counterpartId)
            ->whereNull('read_at')
            ->when(
                $listingId !== null,
                fn ($q) => $q->where('listing_id', $listingId),
            )
            ->update(['read_at' => now()]);
    }

    /**
     * Marks a single message as read, scoped to the caller as its receiver.
     *
     * A message not addressed to the caller is not "findable", so this returns
     * null rather than throwing: the controller treats null as a 404, the same
     * shape as `findOrFail` on the caller's own notifications.
     */
    public function markOneRead(int $userId, int $messageId): ?Message
    {
        $message = Message::query()
            ->where('id', $messageId)
            ->where('receiver_id', $userId)
            ->first();

        if ($message === null) {
            return null;
        }

        if ($message->read_at === null) {
            $message->update(['read_at' => now()]);
        }

        return $message->fresh();
    }

    /**
     * The conversation key for a message: counterpart id only.
     *
     * A conversation is the buyer–seller pair, regardless of listing, so all
     * messages between two users belong to one conversation. `listing_id` is
     * retained as context on each message but does not split conversations.
     */
    private function conversationKey(int $userId, Message $message): string
    {
        return (string) ($message->sender_id === $userId
            ? $message->receiver_id
            : $message->sender_id);
    }

    /**
     * Shapes one group of messages into a conversation payload for the
     * resource.
     *
     * The messages arrive newest-first (the outer query ordered them that
     * way), so `first()` is the latest and the rest are counted for unread.
     *
     * @param  Collection<int, Message>  $messages
     * @return array<string, mixed>
     */
    private function buildConversation(int $userId, Collection $messages): array
    {
        /** @var Message $latest */
        $latest = $messages->first();
        $counterpart = $latest->sender_id === $userId
            ? $latest->receiver
            : $latest->sender;

        $unread = $messages
            ->where('receiver_id', $userId)
            ->whereNull('read_at')
            ->count();

        return [
            'counterpart' => $counterpart,
            'listing_id' => $latest->listing_id,
            'listing_title' => $latest->listing !== null
                ? trim(($latest->listing->livestock_type ?? '').' '.($latest->listing->breed ?? ''))
                : null,
            'last_message' => $latest->body,
            'last_message_at' => $latest->created_at,
            'unread_count' => $unread,
        ];
    }
}