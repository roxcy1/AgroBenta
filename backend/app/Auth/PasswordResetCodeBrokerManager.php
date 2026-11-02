<?php

namespace App\Auth;

use Illuminate\Auth\Passwords\PasswordBrokerManager;

/**
 * Laravel's password broker, using {@see PasswordResetCodeRepository} for tokens.
 */
class PasswordResetCodeBrokerManager extends PasswordBrokerManager
{
    /**
     * @param  array<string, mixed>  $config
     * @return PasswordResetCodeRepository
     */
    protected function createTokenRepository(array $config)
    {
        return new PasswordResetCodeRepository(
            $this->app['db']->connection($config['connection'] ?? null),
            $this->app['hash'],
            $config['table'],
            (string) $this->app['config']['app.key'],
            ($config['expire'] ?? 60) * 60,
            $config['throttle'] ?? 0,
        );
    }
}
