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
