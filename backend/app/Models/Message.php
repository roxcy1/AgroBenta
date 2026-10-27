<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable([
    'sender_id', 'receiver_id', 'listing_id', 'body', 'read_at',
])]
class Message extends Model
{
    /**
     * Get the attributes that should be cast.
     *
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'read_at' => 'datetime',
        ];
    }

    public function sender(): BelongsTo
    {
        return $this->belongsTo(User::class, 'sender_id');
    }

    public function receiver(): BelongsTo
    {
        return $this->belongsTo(User::class, 'receiver_id');
    }

    public function listing(): BelongsTo
    {
        return $this->belongsTo(Listing::class);
    }

    /**
     * Restrict to messages exchanged between two users, in either direction.
     *
     * A conversation is directional by nature, but a thread is not: "show me
     * the messages between A and B" must include both A→B and B→A. Doing this
     * in a scope rather than at each call site means the two WHERE clauses
     * always move together — a controller cannot accidentally filter only one
     * side and silently hide half the thread.
     *
     * @param  Builder<Message>  $query
     * @return Builder<Message>
     */
    public function scopeBetweenUsers(Builder $query, int $userIdA, int $userIdB): Builder
    {
        return $query->where(function (Builder $q) use ($userIdA, $userIdB): void {
            $q->where('sender_id', $userIdA)->where('receiver_id', $userIdB);
        })->orWhere(function (Builder $q) use ($userIdA, $userIdB): void {
            $q->where('sender_id', $userIdB)->where('receiver_id', $userIdA);
        });
    }

    /**
     * Restrict to a specific listing, when the client wants a listing-scoped
     * thread. `listing_id` is nullable on purpose — a general "hello" between
     * two users with no listing behind it is a valid first message.
     *
     * @param  Builder<Message>  $query
     * @return Builder<Message>
     */
    public function scopeForListing(Builder $query, ?int $listingId): Builder
    {
        return $listingId === null
            ? $query->whereNull('listing_id')
            : $query->where('listing_id', $listingId);
    }
}