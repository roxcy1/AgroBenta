<?php

namespace App\Events;

use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Broadcasting\ShouldBroadcast;
use Illuminate\Contracts\Events\ShouldDispatchAfterCommit;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

/**
 * Common behaviour for every real-time event.
 *
 * Every event is:
 *  - broadcast (`ShouldBroadcast`) to a private channel;
 *  - queued (`ShouldQueue`) so a Reverb outage can never fail the request that
 *    wrote the underlying row — the worker retries the broadcast instead;
 *  - dispatched after commit (`ShouldDispatchAfterCommit`) so a rolled-back
 *    database transaction can never broadcast a phantom record.
 *
 * Concrete events only declare `broadcastOn()`, `broadcastAs()` and
 * `broadcastWith()`.
 */
abstract class BroadcastEvent implements ShouldBroadcast, ShouldQueue, ShouldDispatchAfterCommit
{
    use Dispatchable, InteractsWithSockets, Queueable, SerializesModels;
}
