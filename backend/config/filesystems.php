<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Default Filesystem Disk
    |--------------------------------------------------------------------------
    |
    | Here you may specify the default filesystem disk that should be used
    | by the framework. The "local" disk, as well as a variety of cloud
    | based disks are available to your application for file storage.
    |
    */

    'default' => env('FILESYSTEM_DISK', 'local'),

    /*
    |--------------------------------------------------------------------------
    | Filesystem Disks
    |--------------------------------------------------------------------------
    |
    | Below you may configure as many filesystem disks as necessary, and you
    | may even configure multiple disks for the same driver. Examples for
    | most supported storage drivers are configured here for reference.
    |
    | Supported drivers: "local", "ftp", "sftp", "s3"
    |
    */

    'disks' => [

        'local' => [
            'driver' => 'local',
            'root' => storage_path('app/private'),
            'serve' => true,
            'throw' => false,
            'report' => false,
        ],

        'public' => [
            'driver' => 'local',
            'root' => storage_path('app/public'),
            'url' => rtrim(env('APP_URL', 'http://localhost'), '/').'/storage',
            'visibility' => 'public',
            'throw' => false,
            'report' => false,
        ],

        // Listing photos (functional documentation §4.5, contract D-10).
        //
        // A dedicated disk rather than the shared `public` one: photos are a
        // distinct asset class with their own retention questions, and a named
        // disk is what lets the root and driver move to S3 (`LISTING_PHOTOS_DRIVER`)
        // without touching anything else. The default local root sits inside
        // `storage/app/public`, so the existing `storage:link` symlink serves it
        // at `APP_URL/storage/listings/...` with no new nginx or Docker config.
        //
        // Only the *filename* is ever stored in `listings.photos`; the
        // `listings/{id}/` directory is derived from the model and is therefore
        // never written to the column (§4.5: no schema change, the column is
        // sufficient — and it holds the filename, not a path).
        'listing-photos' => [
            'driver' => env('LISTING_PHOTOS_DRIVER', 'local'),
            'root' => env('LISTING_PHOTOS_ROOT', storage_path('app/public/listings')),
            // One `url` key, per Laravel's convention: the local default is the
            // `storage:link` path; a deployment on S3 sets `LISTING_PHOTOS_URL`
            // to its bucket/CDN base, exactly as `AWS_URL` does for the `s3` disk.
            'url' => env(
                'LISTING_PHOTOS_URL',
                rtrim(env('APP_URL', 'http://localhost'), '/').'/storage/listings',
            ),
            'visibility' => 'public',
            // Shared with the `s3` disk above; ignored by the local driver and
            // the only credentials this disk needs when switched to S3.
            'key' => env('AWS_ACCESS_KEY_ID'),
            'secret' => env('AWS_SECRET_ACCESS_KEY'),
            'region' => env('AWS_DEFAULT_REGION'),
            'bucket' => env('AWS_BUCKET'),
            'endpoint' => env('AWS_ENDPOINT'),
            'use_path_style_endpoint' => env('AWS_USE_PATH_STYLE_ENDPOINT', false),
            'throw' => false,
            'report' => false,
        ],

        's3' => [
            'driver' => 's3',
            'key' => env('AWS_ACCESS_KEY_ID'),
            'secret' => env('AWS_SECRET_ACCESS_KEY'),
            'region' => env('AWS_DEFAULT_REGION'),
            'bucket' => env('AWS_BUCKET'),
            'url' => env('AWS_URL'),
            'endpoint' => env('AWS_ENDPOINT'),
            'use_path_style_endpoint' => env('AWS_USE_PATH_STYLE_ENDPOINT', false),
            'throw' => false,
            'report' => false,
        ],

    ],

    /*
    |--------------------------------------------------------------------------
    | Symbolic Links
    |--------------------------------------------------------------------------
    |
    | Here you may configure the symbolic links that will be created when the
    | `storage:link` Artisan command is executed. The array keys should be
    | the locations of the links and the values should be their targets.
    |
    */

    'links' => [
        public_path('storage') => storage_path('app/public'),
    ],

];
