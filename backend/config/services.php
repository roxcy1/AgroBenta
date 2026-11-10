<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Resend, Postmark, AWS, and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    'postmark' => [
        'key' => env('POSTMARK_API_KEY'),
    ],

    'resend' => [
        'key' => env('RESEND_API_KEY'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Private price-prediction service
    |--------------------------------------------------------------------------
    |
    | Laravel depends only on the versioned HTTP contract. It never reads a
    | model filename or CatBoost internals.
    |
    */

    /*
    |--------------------------------------------------------------------------
    | Google Sign-In (mobile)
    |--------------------------------------------------------------------------
    |
    | The OAuth "Web application" client ID the mobile app passes as its
    | `serverClientId`. ID tokens must carry it as their audience. No client
    | secret is needed to verify an ID token, so none is configured here.
    |
    */

    'google' => [
        'client_id' => env('GOOGLE_CLIENT_ID'),
    ],

    'price_prediction' => [
        'url' => env('PRICE_PREDICTION_URL', 'http://ml-service:8002'),
        'connect_timeout' => (int) env('PRICE_PREDICTION_CONNECT_TIMEOUT', 2),
        'timeout' => (int) env('PRICE_PREDICTION_TIMEOUT', 5),
        'contract_version' => env('PRICE_PREDICTION_CONTRACT_VERSION', '1.0'),
    ],

];
