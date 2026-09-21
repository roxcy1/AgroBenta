<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\ListTransactionsRequest;
use App\Http\Resources\TransactionResource;
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
}
