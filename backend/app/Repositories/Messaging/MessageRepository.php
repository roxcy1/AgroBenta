<?php

namespace App\Repositories\Messaging;

use App\Enums\InquiryStatus;
use App\Enums\OfferStatus;
use App\Models\Inquiry;
use App\Models\Listing;
use App\Models\Message;
use App\Models\Offer;
use App\Models\Transaction;
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
     * The inquiries exchanged between the caller and one counterpart.
     *
     * Oldest first, with the listing projection the chat card needs (title,
     * asking price and the stored photo filenames, which the `Listing` accessor
     * resolves to absolute URLs).
     *
     * @return Collection<int, Inquiry>
     */
    public function inquiriesForPair(int $userId, int $counterpartId): Collection
    {
        return Inquiry::query()
            ->where(function ($query) use ($userId, $counterpartId): void {
                $query->where('buyer_id', $userId)->where('seller_id', $counterpartId);
            })
            ->orWhere(function ($query) use ($userId, $counterpartId): void {
                $query->where('buyer_id', $counterpartId)->where('seller_id', $userId);
            })
            ->with(['listing:id,livestock_type,breed,asking_price,photos'])
            ->orderBy('created_at')
            ->orderBy('id')
            ->get();
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
        $pairFacts = $this->pairFacts($userId);

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
                'listing:id,livestock_type,breed,seller_id',
            ])
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->get()
            ->groupBy(fn (Message $m): string => $this->conversationKey($userId, $m))
            ->map(fn (Collection $messages): array => $this->buildConversation(
                $userId,
                $messages,
                $pairFacts,
            ))
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
     * The per-counterpart facts the inbox needs, in one pass.
     *
     * A conversation belongs to a pair of users, so every fact here is keyed by
     * the other user's id:
     *
     *  - `has_inquiry` / `has_transaction` — the pair-level classification the
     *    Inquiries/Transactions chips read. Unchanged by the caller's side.
     *  - `roles` — which side(s) the caller acts on with this counterpart,
     *    derived from the same rows. A pair may be both: the caller bought from
     *    this counterpart and also sells to them. The mode switch shows such a
     *    thread in both modes, which is why this is a set, not a single value.
     *  - `latest_offer` — the newest offer between the pair (any listing), for
     *    the inbox preview. It is a projection, not the full `OfferResource`.
     *  - `eligible_inquiry` — the newest of the caller's own inquiries from
     *    this buyer that has no pending offer, so the seller can start an offer
     *    from the chat without inventing an inquiry id. Null for the buyer side.
     *
     * The lists are bounded by the caller's own rows, and each is a single
     * query — the same shape the previous two counterpart maps used.
     *
     * @return array<int, array{has_inquiry: bool, has_transaction: bool, roles: list<string>, latest_offer: ?Offer, eligible_inquiry: ?Inquiry}>
     */
    private function pairFacts(int $userId): array
    {
        $facts = [];

        $offers = Offer::query()
            ->where(function ($query) use ($userId): void {
                $query->where('buyer_id', $userId)->orWhere('seller_id', $userId);
            })
            ->with('listing:id,livestock_type,breed,asking_price,photos')
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->get();

        $pendingOfferInquiryIds = $offers
            ->filter(fn (Offer $offer): bool => $offer->status === OfferStatus::Pending)
            ->pluck('inquiry_id')
            ->map(fn ($id): int => (int) $id)
            ->flip()
            ->all();

        // Acceptance is permanent: an accepted inquiry is never offered again.
        $acceptedOfferInquiryIds = $offers
            ->filter(fn (Offer $offer): bool => $offer->status === OfferStatus::Accepted)
            ->pluck('inquiry_id')
            ->map(fn ($id): int => (int) $id)
            ->flip()
            ->all();

        $inquiries = Inquiry::query()
            ->where(function ($query) use ($userId): void {
                $query->where('buyer_id', $userId)->orWhere('seller_id', $userId);
            })
            ->with('listing:id,livestock_type,breed,asking_price,photos')
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->get();

        foreach ($inquiries as $inquiry) {
            $isBuyer = (int) $inquiry->buyer_id === $userId;
            $counterpartId = $isBuyer
                ? (int) $inquiry->seller_id
                : (int) $inquiry->buyer_id;

            $facts[$counterpartId] ??= $this->emptyPairFacts();
            $facts[$counterpartId]['has_inquiry'] = true;
            $facts[$counterpartId]['roles'][] = $isBuyer ? 'buyer' : 'seller';

            // Only an open inquiry is actionable or worth previewing; a
            // responded/closed one still links the pair but is history.
            if ($inquiry->status !== InquiryStatus::Open) {
                continue;
            }

            $facts[$counterpartId]['open_inquiry'] ??= $inquiry;

            // Inquiries arrive newest-first, so the first eligible one wins.
            if (
                ! $isBuyer
                && $facts[$counterpartId]['eligible_inquiry'] === null
                && ! isset($pendingOfferInquiryIds[(int) $inquiry->id])
                && ! isset($acceptedOfferInquiryIds[(int) $inquiry->id])
            ) {
                $facts[$counterpartId]['eligible_inquiry'] = $inquiry;
            }
        }

        $transactions = Transaction::query()
            ->where(function ($query) use ($userId): void {
                $query->where('buyer_id', $userId)->orWhere('seller_id', $userId);
            })
            ->get(['buyer_id', 'seller_id']);

        foreach ($transactions as $transaction) {
            $isBuyer = (int) $transaction->buyer_id === $userId;
            $counterpartId = $isBuyer
                ? (int) $transaction->seller_id
                : (int) $transaction->buyer_id;

            $facts[$counterpartId] ??= $this->emptyPairFacts();
            $facts[$counterpartId]['has_transaction'] = true;
            $facts[$counterpartId]['roles'][] = $isBuyer ? 'buyer' : 'seller';
        }

        foreach ($offers as $offer) {
            $isBuyer = (int) $offer->buyer_id === $userId;
            $counterpartId = $isBuyer
                ? (int) $offer->seller_id
                : (int) $offer->buyer_id;

            $facts[$counterpartId] ??= $this->emptyPairFacts();
            $facts[$counterpartId]['roles'][] = $isBuyer ? 'buyer' : 'seller';

            // Newest first, so the first one seen is the latest; the first
            // pending one is the most relevant preview when several exist.
            $facts[$counterpartId]['latest_offer'] ??= $offer;
            if (
                $offer->status === OfferStatus::Pending
                && $facts[$counterpartId]['pending_offer'] === null
            ) {
                $facts[$counterpartId]['pending_offer'] = $offer;
            }
        }

        return $facts;
    }

    /**
     * @return array{has_inquiry: bool, has_transaction: bool, roles: list<string>, latest_offer: ?Offer, pending_offer: ?Offer, eligible_inquiry: ?Inquiry, open_inquiry: ?Inquiry}
     */
    private function emptyPairFacts(): array
    {
        return [
            'has_inquiry' => false,
            'has_transaction' => false,
            'roles' => [],
            'latest_offer' => null,
            'pending_offer' => null,
            'eligible_inquiry' => null,
            'open_inquiry' => null,
        ];
    }

    /**
     * Shapes one group of messages into a conversation payload for the
     * resource.
     *
     * The messages arrive newest-first (the outer query ordered them that
     * way), so `first()` is the latest and the rest are counted for unread.
     *
     * `has_inquiry` and `has_transaction` describe the buyer–seller pair, not
     * the listing on the latest message: a conversation is the counterpart
     * pair, and an inquiry or transaction between those two users is what the
     * inbox filters select. They are computed from the database, never from
     * the message text.
     *
     * `roles` merges the pair-level facts with the ownership of every listing
     * discussed in the thread, so a plain chat that started from a listing is
     * still classified (buyer when the listing belongs to the counterpart,
     * seller when it belongs to the caller). A thread whose role cannot be
     * determined stays empty, and the client shows it in both modes rather
     * than hiding message history.
     *
     * @param  Collection<int, Message>  $messages
     * @param  array<int, array{has_inquiry: bool, has_transaction: bool, roles: list<string>, latest_offer: ?Offer, eligible_inquiry: ?Inquiry}>  $pairFacts
     * @return array<string, mixed>
     */
    private function buildConversation(
        int $userId,
        Collection $messages,
        array $pairFacts,
    ): array {
        /** @var Message $latest */
        $latest = $messages->first();
        $counterpart = $latest->sender_id === $userId
            ? $latest->receiver
            : $latest->sender;

        $unread = $messages
            ->where('receiver_id', $userId)
            ->whereNull('read_at')
            ->count();

        $counterpartId = (int) $counterpart->id;
        $facts = $pairFacts[$counterpartId] ?? $this->emptyPairFacts();

        // The caller's side is a union, never a single value: the same pair can
        // trade in both directions. Listing ownership is the fallback for a
        // thread that has no inquiry/transaction/offer yet.
        $roles = $facts['roles'];
        $listingIds = [];

        foreach ($messages as $message) {
            if ($message->listing_id !== null) {
                $listingIds[(int) $message->listing_id] = true;
            }

            if ($message->listing !== null) {
                $roles[] = (int) $message->listing->seller_id === $userId
                    ? 'seller'
                    : 'buyer';
            }
        }

        /** @var Offer|null $latestOffer */
        $latestOffer = $facts['latest_offer'];
        /** @var Offer|null $pendingOffer */
        $pendingOffer = $facts['pending_offer'];
        /** @var Inquiry|null $openInquiry */
        $openInquiry = $facts['open_inquiry'];

        // The preview names the most relevant listing still in play: a pending
        // offer beats an open inquiry, and both beat the listing on the newest
        // message. That keeps a multi-listing thread honest — the price and
        // status shown belong to the same listing.
        $previewListing = $pendingOffer?->listing
            ?? $openInquiry?->listing
            ?? $latest->listing;

        if ($latestOffer !== null && $latestOffer->listing_id !== null) {
            $listingIds[(int) $latestOffer->listing_id] = true;
        }
        if ($pendingOffer !== null && $pendingOffer->listing_id !== null) {
            $listingIds[(int) $pendingOffer->listing_id] = true;
        }
        if ($openInquiry !== null && $openInquiry->listing_id !== null) {
            $listingIds[(int) $openInquiry->listing_id] = true;
        }

        return [
            'counterpart' => $counterpart,
            'listing_id' => $previewListing?->id ?? $latest->listing_id,
            'listing_title' => $this->listingTitle($previewListing),
            'listing_price' => $previewListing?->asking_price,
            'last_message' => $latest->body,
            'last_message_at' => $latest->created_at,
            'unread_count' => $unread,
            'has_inquiry' => $facts['has_inquiry'],
            'has_transaction' => $facts['has_transaction'],
            'roles' => $this->normaliseRoles($roles),
            'listing_count' => count($listingIds),
            'latest_offer' => $this->offerPreview($latestOffer),
            'eligible_inquiry' => $this->inquiryPreview($facts['eligible_inquiry']),
        ];
    }

    /**
     * Buyer before seller, no duplicates, and only the two known sides.
     *
     * @param  list<string>  $roles
     * @return list<string>
     */
    private function normaliseRoles(array $roles): array
    {
        $unique = array_unique(array_intersect($roles, ['buyer', 'seller']));

        return array_values(array_filter(
            ['buyer', 'seller'],
            fn (string $role): bool => in_array($role, $unique, true),
        ));
    }

    /**
     * The listing's own name, as the marketplace cards show it ("Angus",
     * "Duroc sow"); the livestock type only when the listing has no name.
     */
    private function listingTitle(?Listing $listing): ?string
    {
        if ($listing === null) {
            return null;
        }

        $title = trim($listing->displayLabel());

        return $title === '' ? null : $title;
    }

    /**
     * The small offer projection the inbox preview renders.
     *
     * Deliberately not `OfferResource`: the inbox needs the state and the
     * amount, not the parties or the response timestamps.
     *
     * @return array{id: int, status: string, proposed_amount: string, listing_id: ?int, listing_title: ?string}|null
     */
    private function offerPreview(?Offer $offer): ?array
    {
        if ($offer === null) {
            return null;
        }

        return [
            'id' => (int) $offer->id,
            'status' => $offer->status instanceof OfferStatus
                ? $offer->status->value
                : (string) $offer->status,
            'proposed_amount' => (string) $offer->proposed_amount,
            'listing_id' => $offer->listing_id !== null ? (int) $offer->listing_id : null,
            'listing_title' => $this->listingTitle($offer->listing),
        ];
    }

    /**
     * The inquiry the seller may still turn into an offer.
     *
     * Carries the buyer's original preferences so the offer form can prefill
     * them without a second request (there is no buyer inquiry-detail
     * endpoint).
     *
     * @return array{id: int, listing_id: ?int, listing_title: ?string, asking_price: ?string, payment_method: ?string, collection_method: ?string, preferred_schedule: ?string}|null
     */
    private function inquiryPreview(?Inquiry $inquiry): ?array
    {
        if ($inquiry === null) {
            return null;
        }

        // Read the accessor once: `reset()` takes its argument by reference,
        // and passing the overloaded `$listing->photos` property directly
        // triggers "Indirect modification of overloaded property" (HTTP 500).
        $photos = $inquiry->listing?->photos;

        return [
            'id' => (int) $inquiry->id,
            'listing_id' => $inquiry->listing_id !== null ? (int) $inquiry->listing_id : null,
            'listing_title' => $this->listingTitle($inquiry->listing),
            'asking_price' => $inquiry->listing?->asking_price,
            'listing_photo_url' => is_array($photos) && $photos !== []
                ? (string) reset($photos)
                : null,
            'payment_method' => $inquiry->payment_method?->value,
            'collection_method' => $inquiry->collection_method?->value,
            'preferred_schedule' => $inquiry->preferred_schedule?->toDateString(),
        ];
    }
}
