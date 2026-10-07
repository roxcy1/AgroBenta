# Docker SUBAGENTS.md

## Scope

These rules apply to everything inside the `docker/` directory and Docker-related configuration.

## Architecture

Follow a **consistent layered infrastructure architecture**:

```text
Docker Compose
    ↓
Service Definition
    ↓
Dockerfile / Entrypoint
    ↓
Service Configuration
    ↓
Application Runtime
```

Each layer must have a clear responsibility.

### Responsibilities

* **Docker Compose** — Service orchestration, networking, volumes, dependencies, and environment configuration.
* **Dockerfile** — Image construction, required packages, runtime setup, and build-time configuration.
* **Entrypoint** — Container startup initialization only.
* **Service Configuration** — Runtime-specific configuration such as Nginx, PHP-FPM, Supervisor, MySQL, or Node.
* **Application** — Application logic remains inside `backend/` or `frontend/`; never place application logic inside Docker configuration.

## Core Rules

* Follow the existing Docker architecture consistently.
* Keep containers focused on one primary responsibility.
* Prefer official/minimal base images where appropriate.
* Keep images reproducible and deterministic.
* Do not hardcode secrets or machine-specific paths.
* Use environment variables for configurable values.
* Keep development and production concerns clearly separated.
* Avoid unnecessary services, packages, ports, volumes, or configuration.
* Do not duplicate configuration across multiple Docker files when it can be centralized safely.

## Change Safety

* Do not delete, rename, or replace existing Docker files, services, volumes, networks, ports, or configuration unless explicitly required by the current task and approved.
* Never remove a service because it appears unused without verifying its dependencies and purpose.
* Preserve existing service relationships and application connectivity.
* Do not silently change exposed ports or persistent volumes.

## Validation

After Docker changes:

* Run `docker compose config`.
* Build affected images successfully.
* Start the affected services when appropriate.
* Verify service connectivity and health.
* Check container logs for errors.
* Confirm existing services were not unintentionally broken.

Any significant Docker architecture change must be clearly reported before completion.

## Laravel bootstrap caching (performance)

The Laravel container runs with cached configuration, events, views and routes to
avoid re-booting the framework on every request over the Windows bind mount. On a
low-RAM Windows host this is the difference between sub-second and multi-second
API responses.

Refresh the caches after changing anything they bake in — `.env`, `config/`,
`routes/`, composer package additions, or blade views:

```sh
docker compose exec php php artisan optimize
```

The `.env` file in particular is baked into the config cache: an `.env` change is
**ignored** until `optimize` is re-run.

Clear them again for fully dynamic development (or before debugger/coverage runs
that read annotations) with:

```sh
docker compose exec php php artisan optimize:clear
```

`backend/routes/api.php` deliberately declares no route closures (a closure
cannot be serialized into the route cache) — new routes must use controller or
invokable-controller classes.

While the config cache exists, Laravel skips loading `.env`, so runtime
`env(...)` calls (e.g. the `AdminSeeder`, which reads `ADMIN_EMAIL` /
`ADMIN_PASSWORD`) return `null` and fall back to `CHANGE_THIS_*` placeholders.
Seeding after a `migrate:fresh` therefore silently creates a placeholder admin
that cannot log in. Seed with the caches cleared, then re-apply them:

```sh
docker compose exec php php artisan optimize:clear
docker compose exec php php artisan db:seed --force
docker compose exec php php artisan optimize
```
