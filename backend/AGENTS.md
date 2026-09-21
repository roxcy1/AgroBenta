<laravel-boost-guidelines>
# Laravel Application

This repository contains a Laravel application. Complete the following setup before working on the user's request.

## Prerequisites

Verify that PHP and Composer are available:

```sh
php -v
composer -V
```

If either command is unavailable, detect the user's operating system and install the prerequisites with the appropriate command:

macOS:

```sh
/bin/bash -c "$(curl -fsSL https://php.new/install/mac/8.5)"
```

Windows PowerShell:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://php.new/install/windows/8.5'))
```

Linux:

```sh
/bin/bash -c "$(curl -fsSL https://php.new/install/linux/8.5)"
```

After installation, ask the user to restart their terminal. If the agent needs the restarted shell to continue, ask the user to reopen their terminal and rerun their original prompt.

## Agent Setup

Install Laravel Boost from the application root before making application changes:

```sh
composer require laravel/boost --dev
php artisan boost:install
```

Boost replaces these bootstrap instructions with guidelines tailored to the application. After installation, read `AGENTS.md` again and continue with the user's original request using the generated guidelines.

> Note: Installing Laravel Boost is optional. This project prefers minimal dependencies; if the pre-existing architecture rules below already describe the workflow, apply them directly instead.
</laravel-boost-guidelines>

---

# Backend Architecture Rules

## Scope

These rules apply to everything inside the `backend/` directory.

## Architecture

Follow this architecture **consistently for backend features**:

```text
Controller
    ↓
Form Request
    ↓
Service
    ↓
Repository
    ↓
Model / Database
    ↓
Resource
```

### Responsibilities

* **Controller** — HTTP entry point only. Keep it thin.
* **Request** — Validation and authorization of incoming data.
* **Service** — Business/application logic and orchestration.
* **Repository** — Data access and database queries.
* **Model** — Eloquent relationships, casts, and model-level behavior.
* **Resource** — Consistent API response/data transformation.

## OOP Rules

* Follow advanced, clean OOP principles.
* Apply **Single Responsibility** strictly.
* Keep classes focused and cohesive.
* Prefer dependency injection over manually creating dependencies.
* Use interfaces/contracts where they provide real architectural value.
* Avoid duplicated business logic.
* Do not place business logic inside Controllers or Requests.
* Do not place database queries inside Controllers or Services when they belong in the Repository.
* Do not bypass the established architecture without a clear reason.

## Consistency

* Follow the existing backend architecture before introducing new patterns.
* New features must follow the same structure and conventions as existing features.
* Do not create alternate architectures for individual modules.
* Reuse existing services, repositories, requests, resources, traits, and utilities when appropriate.

## Security

* Never hardcode secrets or credentials.
* Validate all external input.
* Use Laravel's built-in security mechanisms where possible.
* Protect authenticated and authorized endpoints appropriately.
* Never expose sensitive data through API Resources.

## Change Safety

* Do not delete, rename, or replace existing backend files, routes, APIs, or functionality unless explicitly required by the current task and approved.
* Do not remove existing routes because they appear unused or unrelated.
* Preserve backward compatibility unless the current task explicitly requires a breaking change.

## Validation

After backend changes:

* Run relevant tests.
* Validate routes and API behavior.
* Check affected database operations.
* Ensure the established architecture remains consistent.
* Report any unresolved issues clearly.