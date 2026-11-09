<?php

namespace App\Http\Controllers\Api\Transaction;

use App\Enums\TransactionStatus;
use App\Http\Controllers\Controller;
use App\Http\Requests\Transaction\CancelTransactionRequest;
use App\Http\Requests\Transaction\FulfillmentActionRequest;
use App\Http\Requests\Transaction\IndexTransactionRequest;
use App\Http\Requests\Transaction\StoreTransactionRequest;
use App\Http\Resources\MobileTransactionResource;
use App\Models\Listing;
use App\Models\Transaction;
use App\Services\Transaction\TransactionFulfillmentService;
use App\Services\Transaction\TransactionService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * A user's own transactions: browse, create, detail, cancel, and fulfill.
 *
 * Every method resolves the user from the token — never from the body or the
 * query. Responses use `MobileTransactionResource`, never the
 * administrator-facing `TransactionResource`: a mobile reader is a
 * counterparty and sees only the counterparty's contact.
 *
 * The lifecycle itself is not in this class. `TransactionService` owns creation
 * and cancellation; `TransactionFulfillmentService` owns the seller/buyer
 * fulfillment progression and the buyer's receipt confirmation. The ERD's
 * `status` remains `pending`, `completed`, `cancelled`.
 */
class TransactionController extends Controller
{
    public function __construct(
        private readonly TransactionService $transactions,
        private readonly TransactionFulfillmentService $fulfillment,
    ) {
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
     * Seller starts preparing the livestock.
     */
    public function preparing(FulfillmentActionRequest $request, string $transaction): JsonResponse
    {
        return $this->fulfillmentResponse(
            $this->fulfillment->markPreparing(
                (int) $transaction,
                $request->user(),
            ),
            'Transaction is preparing.',
        );
    }

    /**
     * Seller marks a pickup-flow transaction ready for pickup.
     */
    public function readyForPickup(FulfillmentActionRequest $request, string $transaction): JsonResponse
    {
        return $this->fulfillmentResponse(
            $this->fulfillment->markReadyForPickup(
                (int) $transaction,
                $request->user(),
            ),
            'Transaction is ready for pickup.',
        );
    }

    /**
     * Seller confirms handover in a pickup-flow transaction.
     */
    public function pickedUp(FulfillmentActionRequest $request, string $transaction): JsonResponse
    {
        return $this->fulfillmentResponse(
            $this->fulfillment->confirmHandover(
                (int) $transaction,
                $request->user(),
            ),
            'Transaction marked as picked up.',
        );
    }

    /**
     * Seller marks a delivery-flow transaction on the way.
     */
    public function onTheWay(FulfillmentActionRequest $request, string $transaction): JsonResponse
    {
        return $this->fulfillmentResponse(
            $this->fulfillment->markOnTheWay(
                (int) $transaction,
                $request->user(),
            ),
            'Transaction is on the way.',
        );
    }

    /**
     * Seller marks a delivery-flow transaction delivered.
     */
    public function delivered(FulfillmentActionRequest $request, string $transaction): JsonResponse
    {
        return $this->fulfillmentResponse(
            $this->fulfillment->markDelivered(
                (int) $transaction,
                $request->user(),
            ),
            'Transaction marked as delivered.',
        );
    }

    /**
     * Buyer confirms receipt after pickup/delivery. This completes the sale.
     */
    public function complete(FulfillmentActionRequest $request, string $transaction): JsonResponse
    {
        return $this->fulfillmentResponse(
            $this->fulfillment->confirmReceived(
                (int) $transaction,
                $request->user(),
            ),
            'Transaction completed.',
        );
    }

    private function fulfillmentResponse(Transaction $transaction, string $message): JsonResponse
    {
        return response()->json([
            'success' => true,
            'message' => $message,
            'data' => new MobileTransactionResource($transaction),
        ], 200);
    }
}
