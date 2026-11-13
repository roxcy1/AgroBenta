#!/usr/bin/env bash
# Build and (re)start AgroBenta on the production server.
#
#   cd ~/AgroBenta && git pull origin main && ./deploy.sh
#
# Safe to run again and again: every step is idempotent. Needs the root .env
# and backend/.env in place first (see docs/DEPLOYMENT.md). Never seeds data.

set -euo pipefail
cd "$(dirname "$0")"

COMPOSE=(docker compose -f compose.yaml -f compose.prod.yaml)

# Read one KEY=value from an env file, without quotes.
env_value() {
    grep -E "^$1=" "$2" | tail -n 1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'
}

for file in .env backend/.env; do
    if [[ ! -f "$file" ]]; then
        echo "Missing $file. See docs/DEPLOYMENT.md." >&2
        exit 1
    fi
done

SITE_DOMAIN="$(env_value SITE_DOMAIN .env)"
REVERB_APP_KEY="$(env_value REVERB_APP_KEY backend/.env)"

if [[ -z "$SITE_DOMAIN" || -z "$REVERB_APP_KEY" ]]; then
    echo "Set SITE_DOMAIN in .env and REVERB_APP_KEY in backend/.env." >&2
    exit 1
fi

echo "==> Building images"
"${COMPOSE[@]}" build

echo "==> Starting the database, cache, ML service and PHP"
"${COMPOSE[@]}" up -d --wait mysql redis ml-service php

echo "==> Installing PHP packages (no dev tools)"
"${COMPOSE[@]}" exec -T php composer install --no-dev --no-interaction --optimize-autoloader </dev/null

echo "==> Letting PHP write storage/ and bootstrap/cache/ and read .env"
# PHP-FPM, the queue worker and Reverb all run as www-data. backend/.env stays
# owned by the server user; www-data gets read access through its group only.
"${COMPOSE[@]}" exec -T php sh -c \
    'chown -R www-data:www-data storage bootstrap/cache && chmod -R ug+rwX storage bootstrap/cache && chgrp www-data .env && chmod 640 .env' </dev/null

artisan() {
    "${COMPOSE[@]}" exec -T -u www-data php php artisan "$@" </dev/null
}

if [[ -z "$(env_value APP_KEY backend/.env)" ]]; then
    echo "==> Generating APP_KEY"
    "${COMPOSE[@]}" exec -T php php artisan key:generate --force </dev/null
fi

echo "==> Running database migrations"
artisan migrate --force

echo "==> Linking public storage"
artisan storage:link 2>/dev/null || true

echo "==> Caching config, routes, events and views"
artisan optimize

echo "==> Building the Admin Web for https://$SITE_DOMAIN"
docker run --rm \
    --user "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    -e VITE_API_URL="https://$SITE_DOMAIN/api" \
    -e VITE_REVERB_HOST="$SITE_DOMAIN" \
    -e VITE_REVERB_PORT=443 \
    -e VITE_REVERB_SCHEME=https \
    -e VITE_REVERB_APP_KEY="$REVERB_APP_KEY" \
    -v "$PWD/frontend:/app" \
    -w /app \
    node:22-alpine \
    sh -c 'npm ci --no-audit --no-fund && npm run build'

echo "==> Stopping development-only services, if running"
"${COMPOSE[@]}" rm --stop --force phpmyadmin node >/dev/null 2>&1 || true

echo "==> Starting everything"
"${COMPOSE[@]}" up -d --remove-orphans

# Pick up the new code in the long-running workers.
"${COMPOSE[@]}" restart queue reverb

echo "==> Done"
"${COMPOSE[@]}" ps --format 'table {{.Service}}\t{{.Status}}'
echo "Open https://$SITE_DOMAIN"
