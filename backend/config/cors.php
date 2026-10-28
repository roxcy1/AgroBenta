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

    'paths' => ['api/*', 'storage/*'],

    'allowed_methods' => ['*'],

    'allowed_origins' => [
        'http://localhost:5174',
       'http://localhost:8080',
    ],

    'allowed_origins_patterns' => [
        // Development web origins served from the local machine over plain HTTP.
        // Flutter Web (`flutter run -d chrome` or `--web-port`) and the Admin Web
        // Vite dev server may be reached via `localhost` or via the machine's
        // LAN IP when accessed from another device on the same network. Matching
        // private IP ranges avoids hardcoding any one developer's address.
        'http://localhost:\d+',
        'http://10\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d+',
        'http://192\.168\.\d{1,3}\.\d{1,3}:\d+',
        'http://172\.1[6-9]\.\d{1,3}\.\d{1,3}:\d+',
        'http://172\.2[0-9]\.\d{1,3}\.\d{1,3}:\d+',
        'http://172\.3[0-1]\.\d{1,3}\.\d{1,3}:\d+',
    ],

    'allowed_headers' => ['*'],

    'exposed_headers' => [],

    'max_age' => 0,

    'supports_credentials' => false,

];
