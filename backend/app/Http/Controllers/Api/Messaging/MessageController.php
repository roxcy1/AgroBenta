<?php

namespace App\Http\Controllers\Api\Messaging;

use App\Http\Controllers\Controller;
use App\Http\Requests\Messaging\IndexMessageRequest;
use App\Http\Requests\Messaging\StoreMessageRequest;
use App\Http\Resources\MessageResource;
use App\Models\User;
use App\Services\Messaging\MessagingService;
use Illuminate\Http\JsonResponse;

/**
 * The messages themselves.
 *
 * Three actions:
 *
 *  - `index` — the thread with a counterpart, optionally narrowed to a listing
 *  - `store` — send a message
 *  - `markRead` — mark one message as read
 *
 * Every route resolves "me" from the token. The counterpart id in the URL is
 * always checked against the caller: the caller can only see a thread they are
 * part of, because the query filters on both directions of the pair.
 */
class MessageController extends Controller
{
    public function __construct(private readonly MessagingService $messaging)
    {
        //
    }

    /**
     * `GET /api/conversations/{userId}/messages` — the thread with one user.
     */
    public function index(
        IndexMessageRequest $request,
        int $userId,
    ): JsonResponse {
        $paginator = $this->messaging->threadBetween(
            $request->user(),
            $userId,
            $request->validated('listing_id'),
            $request->validated('per_page', 30),
        );

        return response()->json([
            'success' => true,
            'data' => [
                'messages' => MessageResource::collection($paginator->items()),
                'pagination' => [
                    'current_page' => $paginator->currentPage(),
                    'last_page' => $paginator->lastPage(),
                    'per_page' => $paginator->perPage(),
                    'total' => $paginator->total(),
                ],
            ],
        ], 200);
    }

    /**
     * `POST /api/messages` — send a message.
     *
     * The receiver id is validated by `StoreMessageRequest` (exists + not-self),
     * so the service can trust it. The response carries the stored message
     * with its relations loaded, so the client can render it without a second
     * request.
     */
    public function store(StoreMessageRequest $request): JsonResponse
    {
        $sender = $request->user();
        $receiver = User::findOrFail($request->validated('receiver_id'));

        $message = $this->messaging->sendMessage(
            $sender,
            $receiver,
            $request->validated('body'),
            $request->validated('listing_id'),
        );

        return response()->json([
            'success' => true,
            'message' => 'Message sent.',
            'data' => new MessageResource($message),
        ], 201);
    }

    /**
     * `PATCH /api/messages/{id}/read` — mark one message as read.
     *
     * A message not addressed to the caller answers 404, not 403: the caller
     * is not entitled to know that the id exists, the same rule the
     * notification endpoints follow.
     */
    public function markRead(int $id): JsonResponse
    {
        $message = $this->messaging->markOneRead(request()->user(), $id);

        if ($message === null) {
            abort(404, 'Message not found.');
        }

        return response()->json([
            'success' => true,
            'message' => 'Message marked as read.',
            'data' => new MessageResource($message),
        ], 200);
    }
}