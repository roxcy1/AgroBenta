<?php

namespace Tests;

use Illuminate\Foundation\Testing\TestCase as BaseTestCase;
use Illuminate\Support\Facades\Auth;

abstract class TestCase extends BaseTestCase
{
    /**
     * Issue the request with a clean auth-guard cache.
     *
     * Each real HTTP request boots a fresh application, so its guard starts
     * empty. The test kernel keeps one application instance alive for the
     * whole test, and `RequestGuard` caches the user resolved from the first
     * request — a later request with a different token would otherwise still
     * act as the first user. Dropping the cached guards before every request
     * keeps multi-user tests honest.
     */
    public function call(
        $method,
        $uri,
        $parameters = [],
        $cookies = [],
        $files = [],
        $server = [],
        $content = null,
    ) {
        Auth::forgetGuards();

        return parent::call($method, $uri, $parameters, $cookies, $files, $server, $content);
    }
}
