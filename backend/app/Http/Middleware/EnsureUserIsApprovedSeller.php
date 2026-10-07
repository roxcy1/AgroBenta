<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Refuses any request from a user who is not an approved seller.
 *
 * The counterpart to `EnsureUserIsAdmin`, and deliberately built the same way:
 * one place decides, and it reads a method on the model rather than inspecting
 * a field name, so a column rename cannot quietly turn the check into a no-op.
 *
 * `User::isApprovedSeller()` is the same predicate the seller-verification
 * approval writes on (`AdminSellerVerificationService` sets
 * `seller_capability = seller`), so the gate cannot drift from the workflow that
 * grants it. It is a capability, not a role: an approved seller is still
 * `role = user` under the single-account model (functional documentation §2.6).
 *
 * `403` rather than `404` is the documented answer for a buyer calling a seller
 * endpoint (contract §5.4), and it says something true: the token is valid, this
 * account simply has not been approved to sell.
 */
class EnsureUserIsApprovedSeller
{
    /**
     * Handle an incoming request.
     */
    public function handle(Request $request, Closure $next): Response
    {
        abort_unless(
            $request->user()?->isApprovedSeller(),
            403,
            'An approved seller account is required to manage listings.',
        );

        return $next($request);
    }
}
