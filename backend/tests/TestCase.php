<?php

namespace Tests;

use Illuminate\Foundation\Testing\TestCase as BaseTestCase;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use RuntimeException;

abstract class TestCase extends BaseTestCase
{
    /**
     * Fail closed before RefreshDatabase/DatabaseMigrations/DatabaseTruncation
     * can touch a database.
     *
     * This runs after the application has booted but before Laravel's
     * setUpTraits() invokes any destructive test trait. It therefore also
     * catches a cached config that points at the development MySQL database.
     */
    protected function setUpTraits()
    {
        $this->assertSafeTestDatabase();

        return parent::setUpTraits();
    }

    private function assertSafeTestDatabase(): void
    {
        $environment = app()->environment();
        $connectionName = config('database.default');
        $connection = config("database.connections.{$connectionName}", []);
        $driver = $connection['driver'] ?? null;
        $database = $connection['database'] ?? null;

        $safeConfiguration = $environment === 'testing'
            && $driver === 'sqlite'
            && $database === ':memory:';

        if (! $safeConfiguration) {
            throw new RuntimeException(sprintf(
                'REFUSING TO RUN TESTS: unsafe database configuration. '.
                'Effective environment=%s, connection=%s, driver=%s, database=%s. '.
                'Tests require environment=testing, connection=sqlite, database=:memory:. '.
                'Clear cached configuration with `php artisan optimize:clear` and use '.
                '`composer test` or run `php artisan test` only after clearing the cache.',
                var_export($environment, true),
                var_export($connectionName, true),
                var_export($driver, true),
                var_export($database, true),
            ));
        }

        // Verify the effective connection, not only the config array.
        $actualDriver = DB::connection()->getDriverName();
        $actualDatabase = DB::connection()->getDatabaseName();

        if ($actualDriver !== 'sqlite' || $actualDatabase !== ':memory:') {
            throw new RuntimeException(sprintf(
                'REFUSING TO RUN TESTS: effective database is driver=%s, database=%s. '.
                'Expected sqlite/:memory:.',
                var_export($actualDriver, true),
                var_export($actualDatabase, true),
            ));
        }
    }

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
