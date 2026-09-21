#!/bin/sh
set -e

# This entrypoint does NOT scaffold Laravel. It only decides what to do
# when the container's default command (php-fpm) is started without an
# app present yet -- everything else (explicit commands you pass via
# "docker compose run --rm php <command>") is executed as-is, untouched.

if [ "$*" = "php-fpm" ] && [ ! -f "/var/www/html/artisan" ]; then
    echo ">> No Laravel app found in ./backend yet."
    echo ">> Scaffold it first (run from your host machine, project root):"
    echo ">>   docker compose run --rm php composer create-project laravel/laravel ."
    echo ">>   docker compose run --rm php php artisan install:api --no-interaction"
    echo ">>   docker compose run --rm php php artisan key:generate"
    echo ">>"
    echo ">> php-fpm will start anyway below, but nginx on :8000 will 404 until"
    echo ">> the app exists. This message just saves you a confusing debug."
fi

exec "$@"
