<?php

use App\Http\Middleware\EnsureUserIsAdmin;
use App\Http\Middleware\EnsureUserIsApprovedSeller;
use App\Http\Middleware\ForceJsonResponse;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;
use Laravel\Sanctum\Http\Middleware\CheckAbilities;
use Laravel\Sanctum\Http\Middleware\CheckForAnyAbility;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    // Reverb channel subscription is authenticated with the same Sanctum bearer
    // token as the REST API, not the session `web` guard. `auth:sanctum` (rather
    // than the default `web` middleware) is what lets the Flutter/React clients
    // authenticate a `private-*` subscription without a session or CSRF cookie.
    ->withBroadcasting(
        __DIR__.'/../routes/channels.php',
        ['middleware' => ['auth:sanctum']],
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // Registered globally (rather than on the `api` group) because Laravel
        // sorts the route middleware stack by priority, hoisting the
        // authentication middleware above ordinary group middleware. Global
        // middleware is guaranteed to run first.
        $middleware->prepend(ForceJsonResponse::class);

        // In production every request reaches Laravel through Caddy (HTTPS)
        // and nginx on the private Docker network. Trusting the forwarded
        // headers from private addresses only lets Laravel see the real
        // scheme (https) and the visitor's IP (for rate limiting), while a
        // client calling from the internet cannot fake them. nginx publishes
        // no port in production, so only Caddy can reach it.
        $middleware->trustProxies(at: [
            '10.0.0.0/8',
            '172.16.0.0/12',
            '192.168.0.0/16',
        ]);

        $middleware->alias([
            'abilities' => CheckAbilities::class,
            'ability' => CheckForAnyAbility::class,
            'admin' => EnsureUserIsAdmin::class,
            // The seller-side counterpart of `admin`. Named for the capability
            // rather than the role, because under the single-account model a
            // seller is still `role = user`; what gates the routes is
            // `seller_capability = seller`.
            'seller' => EnsureUserIsApprovedSeller::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*') || $request->expectsJson(),
        );
    })->create();
