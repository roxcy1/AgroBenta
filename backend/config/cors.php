<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Cross-Origin Resource Sharing (CORS) Configuration
    |--------------------------------------------------------------------------
    |
    | Two browser clients call the API directly, and the origin list has to
    | cover both — the API authenticates with stateless Sanctum bearer tokens,
    | so `supports_credentials` stays false and no cookie is involved.
    |
    |   http://localhost:5174  the Admin Web (React + Vite dev server)
    |   http://localhost:8080  the Flutter Web dev server (`flutter run -d chrome`)
    |
    | Flutter Web is listed explicitly rather than by widening this to a
    | `localhost:<any port>` pattern. The port is Flutter's documented dev-server
    | default and is stable, so the allowance stays as narrow as the
    | application that needs it. If the dev server is started on a different
    | port with `--web-port`, add that origin here as well.
    |
    | Native Flutter builds (Android, iOS) are not browsers and are not subject
    | to the same-origin policy, so they need no entry.
    |
    */

    'paths' => ['api/*'],

    'allowed_methods' => ['*'],

    'allowed_origins' => [
        'http://localhost:5174',
        'http://localhost:8080',
    ],

    'allowed_origins_patterns' => [],

    'allowed_headers' => ['*'],

    'exposed_headers' => [],

    'max_age' => 0,

    'supports_credentials' => false,

];
