<?php

namespace App\Http\Controllers\Api\Messaging;

use App\Http\Controllers\Controller;
use App\Http\Requests\Messaging\MarkMessagesReadRequest;
use App\Http\Resources\ConversationResource;
use App\Services\Messaging\MessagingService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The caller's own conversations.
 *
 * A conversation is not a stored entity — it is derived from the messages
 * that touch the caller. Every route resolves "me" from the token, so one
 * account cannot list another account's conversations, and the counterpart
 * id in the path is a filter, not a key to somebody else's data.
 */
class ConversationController extends Controller
{
    public function __construct(private readonly MessagingService $messaging)
    {
        //
    }

    /**
     * `GET /api/conversations` — every thread the caller is part of.
     *
     * No pagination: the number of active threads a single user has is small
     * (bounded by the number of distinct people they have messaged), and a
     * page-based list would force the client to handle a paginated view for a
     * screen that almost always fits on one page.
     */
    public function index(Request $request): JsonResponse
    {
        $conversations = $this->messaging->conversationsFor($request->user());

        return response()->json([
            'success' => true,
            'data' => [
                'conversations' => ConversationResource::collection($conversations),
            ],
        ], 200);
    }

    /**
     * `POST /api/conversations/{userId}/read` — mark every unread message from
     * a counterpart as read.
     *
     * The counterpart id is validated by the route (`whereNumber`), but not
     * against `users`: a nonexistent counterpart is not an error — it just
     * means zero rows to update. The caller learns nothing from a 404 that
     * they could not learn from an empty thread, and treating "no messages"
     * as success is what makes tapping into an empty thread idempotent.
     */
    public function markRead(
        MarkMessagesReadRequest $request,
        int $userId,
    ): JsonResponse {
        $updated = $this->messaging->markThreadRead(
            $request->user(),
            $userId,
            $request->validated('listing_id'),
        );

        return response()->json([
            'success' => true,
            'message' => 'Thread marked as read.',
            'data' => ['updated' => $updated],
        ], 200);
    }
}