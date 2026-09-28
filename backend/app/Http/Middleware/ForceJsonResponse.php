<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Treat requests in the `api` group as JSON requests.
 *
 * This application exposes no `login` route, so when Laravel's authentication
 * middleware treats a request as a browser request it falls back to
 * `redirect()->guest(route('login'))` and throws `RouteNotFoundException`,
 * surfacing a 500 instead of a 401. The exception handler is already
 * configured to render JSON for every `api/*` path; this aligns
 * `expectsJson()` with that intent so unauthenticated API failures stay on the
 * documented 401 path.
 */
class ForceJsonResponse
{
    public function handle(Request $request, Closure $next): Response
    {
        if ($request->is('api/*')) {
            $request->headers->set('Accept', 'application/json');
        }

        return $next($request);
    }
}
