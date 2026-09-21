#!/bin/sh
set -e

# This entrypoint does NOT scaffold React/Vite. It only prevents the default
# long-running dev command from crash-looping when there's no project yet.
# Any explicit command you pass -- e.g.
#   docker compose run --rm node npm create vite@latest . -- --template react
# -- runs immediately, untouched, no interception at all.

if [ "$*" = "npm run dev -- --host 0.0.0.0" ] && [ ! -f "/app/package.json" ]; then
    echo ">> No frontend project found in ./frontend yet."
    echo ">> Scaffold it first (run from your host machine, project root):"
    echo ">>   docker compose run --rm node npm create vite@latest . -- --template react"
    echo ">>   docker compose run --rm node npm install"
    echo ">>"
    echo ">> Idling so this container doesn't crash-loop. Once the project"
    echo ">> exists, run: docker compose restart node"
    tail -f /dev/null
fi

exec "$@"
