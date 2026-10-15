<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\ListTransactionsRequest;
use App\Http\Resources\TransactionResource;
use App\Models\Transaction;
use App\Services\Admin\AdminTransactionService;
use Illuminate\Http\JsonResponse;

class TransactionController extends Controller
{
    public function __construct(private readonly AdminTransactionService $transactions)
    {
        //
    }

    /**
     * List transactions with optional search, filtering, and pagination.
     */
    public function index(ListTransactionsRequest $request): JsonResponse
    {
        $paginator = $this->transactions->listTransactions(
            search: $request->validated('search'),
            status: $request->validated('status'),
            dateFrom: $request->validated('date_from'),
            dateTo: $request->validated('date_to'),
            perPage: $request->validated('per_page', 15),
        );

        return response()->json([
            'success' => true,
            'data' => [
                'transactions' => TransactionResource::collection($paginator->items()),
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
     * Show a single transaction.
     *
     * Deep-link support: the activity feed links to a transaction by id, so the
     * administrator's detail dialog opens from this record rather than from a
     * row that may not be on the page they were sent to.
     */
    public function show(Transaction $transaction): JsonResponse
    {
        $transaction->load([
            'buyer:id,name,email',
            'seller:id,name,email',
            'listing:id,livestock_type,breed',
        ]);

        return response()->json([
            'success' => true,
            'data' => new TransactionResource($transaction),
        ], 200);
    }
}
