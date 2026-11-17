<?php

namespace Tests\Feature\Realtime;

use App\Events\ActivityRecorded;
use App\Events\BroadcastEvent;
use App\Events\InquiryCreated;
use App\Events\ListingInventoryUpdated;
use App\Events\MessageSent;
use App\Events\NotificationCreated;
use App\Events\OfferCreated;
use App\Events\OfferUpdated;
use App\Events\TransactionCreated;
use App\Events\TransactionUpdated;
use Illuminate\Contracts\Broadcasting\ShouldBroadcast;
use Illuminate\Contracts\Events\ShouldDispatchAfterCommit;
use Illuminate\Contracts\Queue\ShouldQueue;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use ReflectionClass;
use Tests\TestCase;

/**
 * Phase 5 — the resilience contract every real-time event must satisfy.
 *
 * A broadcast must never fail or block the HTTP request that wrote the row, and
 * a rolled-back transaction must never broadcast a phantom record. Both are
 * guaranteed by `ShouldQueue` + `ShouldDispatchAfterCommit`, so this test pins
 * those interfaces on every event (a regression here is silent otherwise).
 */
class BroadcastContractTest extends TestCase
{
    /**
     * @return array<string, array{class-string}>
     */
    public static function eventClasses(): array
    {
        return [
            'MessageSent' => [MessageSent::class],
            'InquiryCreated' => [InquiryCreated::class],
            'OfferCreated' => [OfferCreated::class],
            'OfferUpdated' => [OfferUpdated::class],
            'TransactionCreated' => [TransactionCreated::class],
            'TransactionUpdated' => [TransactionUpdated::class],
            'ListingInventoryUpdated' => [ListingInventoryUpdated::class],
            'NotificationCreated' => [NotificationCreated::class],
            'ActivityRecorded' => [ActivityRecorded::class],
        ];
    }

    #[Test]
    #[DataProvider('eventClasses')]
    public function broadcast_events_are_queued_and_dispatched_after_commit(string $eventClass): void
    {
        $reflection = new ReflectionClass($eventClass);

        $this->assertTrue(
            $reflection->implementsInterface(ShouldBroadcast::class),
            "$eventClass must be broadcastable.",
        );
        $this->assertTrue(
            $reflection->implementsInterface(ShouldQueue::class),
            "$eventClass must be queued so a Reverb outage cannot fail the request.",
        );
        $this->assertTrue(
            $reflection->implementsInterface(ShouldDispatchAfterCommit::class),
            "$eventClass must dispatch after commit so a rollback cannot broadcast a phantom.",
        );
        $this->assertTrue(
            $reflection->isSubclassOf(BroadcastEvent::class),
            "$eventClass must extend BroadcastEvent.",
        );
    }
}
