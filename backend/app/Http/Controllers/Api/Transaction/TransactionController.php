<?php

namespace App\Http\Controllers\Api\Transaction;

use App\Enums\TransactionStatus;
use App\Http\Controllers\Controller;
use App\Http\Requests\Transaction\CancelTransactionRequest;
use App\Http\Requests\Transaction\IndexTransactionRequest;
use App\Http\Requests\Transaction\StoreTransactionRequest;
use App\Http\Resources\MobileTransactionResource;
use App\Models\Listing;
use App\Services\Transaction\TransactionService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * A user's own transactions: browse, create, detail, cancel.
 *
 * Every method resolves the user from the token — never from the body or the
 * query. Responses use `MobileTransactionResource`, never the
 * administrator-facing `TransactionResource`: a mobile reader is a
 * counterparty and sees only the counterparty's contact.
 *
 * The lifecycle itself is not in this class. It belongs to
 * [TransactionService], which is the only place that knows creation is
 * buyer-initiated, the amount is server-derived, and cancellation is the only
 * transition. Completion is absent by decision (OQ-15): there is no `complete`
 * method here, and no route below can express that transition.
 */
class TransactionController extends Controller
{
    public function __construct(private readonly TransactionService $transactions)
    {
        //
    }

    /**
     * List the authenticated user's transactions in every status.
     *
     * `role` narrows to the caller's buyer side or seller side; absent means
     * both. `status` narrows to one lifecycle state for the tabbed screen.
     */
    public function index(IndexTransactionRequest $request): JsonResponse
    {
        $status = $request->validated('status');

        $paginator = $this->transactions->listForUser(
            $request->user(),
            $request->validated('role'),
            $status === null ? null : TransactionStatus::from($status),
            (int) $request->validated('per_page', 15),
        );

        return response()->json([
            'success' => true,
            'data' => [
                'transactions' => MobileTransactionResource::collection($paginator->items()),
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
     * Create a pending transaction for the authenticated buyer.
     */
    public function store(StoreTransactionRequest $request): JsonResponse
    {
        $listing = Listing::query()->find($request->validated('listing_id'));

        if ($listing === null) {
            abort(404, 'Listing not found.');
        }

        $transaction = $this->transactions->create(
            $request->user(),
            $listing,
            (int) $request->validated('quantity'),
        );

        return response()->json([
            'success' => true,
            'message' => 'Transaction created and pending.',
            'data' => new MobileTransactionResource($transaction),
        ], 201);
    }

    /**
     * View one transaction the caller is a party to.
     *
     * A transaction the viewer is not party to and one that does not exist
     * both produce the same 404, so one pair's transactions cannot be
     * discovered by guessing ids.
     */
    public function show(Request $request, string $transaction): JsonResponse
    {
        $found = $this->transactions->findForUser((int) $transaction, $request->user());

        if ($found === null) {
            abort(404, 'Transaction not found.');
        }

        return response()->json([
            'success' => true,
            'data' => new MobileTransactionResource($found),
        ], 200);
    }

    /**
     * Cancel a pending transaction. Either party may cancel [D-15 rule 5].
     *
     * Irreversible: a cancelled transaction stays cancelled.
     */
    public function cancel(CancelTransactionRequest $request, string $transaction): JsonResponse
    {
        $found = $this->transactions->findForUser((int) $transaction, $request->user());

        if ($found === null) {
            abort(404, 'Transaction not found.');
        }

        $cancelled = $this->transactions->cancel($found, $request->user());

        return response()->json([
            'success' => true,
            'message' => 'Transaction cancelled.',
            'data' => new MobileTransactionResource($cancelled),
        ], 200);
    }

    /**
     * The completion transition, explicitly unavailable.
     *
     * [D-15] rule 4 requires "the appropriate transaction confirmation" without
     * naming the actor (OQ-15). Until that is answered the transition stays
     * unimplemented, and an explicit 501 says so rather than a 404 that would
     * read as "no such route". The mobile client never calls this; it hides
     * the affordance entirely.
     */
    public function complete(): JsonResponse
    {
        abort(501, 'Transaction completion is not yet available.');
    }
}
