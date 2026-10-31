<?php

namespace App\Http\Controllers\Api\Notification;

use App\Http\Controllers\Controller;
use App\Http\Requests\Notification\IndexNotificationRequest;
use App\Http\Resources\NotificationResource;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The authenticated user's own notifications.
 *
 * Every endpoint resolves the user from the token, never from a route
 * parameter. A notification id is the only id in any path, and the controller
 * checks it against the caller's own list — an id belonging to somebody else
 * answers 404, not 403, because the existence of a notification that belongs
 * to another user is not information this caller is entitled to.
 *
 * The notifications table is Laravel's standard one (UUID primary key,
 * notifiable_type/notifiable_id polymorphic, data as a JSON string). All
 * the filtering happens in $user->notifications(), which is already scoped
 * to the caller.
 */
class NotificationController extends Controller
{
    /**
     * GET /api/notifications — paginated list of the caller's notifications.
     */
    public function index(IndexNotificationRequest $request): JsonResponse
    {
        $user = $request->user();

        $query = $user->notifications()->latest();

        if ($request->has('unread')) {
            $unread = $request->boolean('unread');

            $query = $unread
                ? $user->unreadNotifications()->latest()
                : $user->readNotifications()->latest();
        }

        if ($request->filled('type')) {
            $type = (string) $request->validated('type');
            $query = $query->where('data->type', $type);
        }

        $perPage = (int) $request->validated('per_page', 15);
        $paginator = $query->paginate($perPage);

        return response()->json([
            'success' => true,
            'data' => [
                'notifications' => NotificationResource::collection($paginator->items()),
                'pagination' => [
                    'current_page' => $paginator->currentPage(),
                    'last_page' => $paginator->lastPage(),
                    'per_page' => $paginator->perPage(),
                    'total' => $paginator->total(),
                ],
                'unread_count' => $user->unreadNotifications()->count(),
            ],
        ], 200);
    }

    /**
     * GET /api/notifications/unread-count — small endpoint for the nav badge.
     *
     * Deliberately separate from index: the badge must update after every
     * event that could produce a notification, and fetching a full page to read
     * one integer would be wasteful. This endpoint is small enough to be polled.
     */
    public function unreadCount(Request $request): JsonResponse
    {
        return response()->json([
            'success' => true,
            'data' => [
                'count' => $request->user()->unreadNotifications()->count(),
            ],
        ], 200);
    }

    /**
     * PATCH /api/notifications/{id}/read — mark one notification as read.
     *
     * findOrFail on the caller's own notifications means an id belonging to
     * another user answers 404. That is the right answer: the caller is not
     * entitled to learn that the id exists.
     */
    public function markAsRead(Request $request, string $id): JsonResponse
    {
        $notification = $request->user()
            ->notifications()
            ->findOrFail($id);

        $notification->markAsRead();

        return response()->json([
            'success' => true,
            'message' => 'Notification marked as read.',
            'data' => new NotificationResource($notification->fresh()),
        ], 200);
    }

    /**
     * POST /api/notifications/read-all — mark every unread notification as read.
     *
     * Returns the number of notifications updated so the caller can update
     * the unread badge without making another request.
     */
    public function markAllAsRead(Request $request): JsonResponse
    {
        $count = $request->user()
            ->unreadNotifications()
            ->update(['read_at' => now()]);

        return response()->json([
            'success' => true,
            'message' => 'All notifications marked as read.',
            'data' => ['count' => $count],
        ], 200);
    }

    /**
     * DELETE /api/notifications/{id} — delete one notification.
     *
     * Scoped the same way as markAsRead: another user's id is a 404.
     */
    public function destroy(Request $request, string $id): JsonResponse
    {
        $notification = $request->user()
            ->notifications()
            ->findOrFail($id);

        $notification->delete();

        return response()->json([
            'success' => true,
            'message' => 'Notification deleted.',
        ], 200);
    }
}
