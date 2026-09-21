# Frontend — AI Agent Instructions

## Scope

This file applies only to `frontend/`.

The frontend is a React + Vite application.

Inspect existing code before making changes.

Follow existing architecture, naming, UI, and coding patterns.

## Existing Architecture

Reuse the existing feature-based structure where applicable:

```text
features/
→ API client / API functions
→ React Query hooks
→ TypeScript types
→ Shared feature components

pages/
→ Compose features and existing UI components
```

Do not create parallel API clients, query systems, state systems, or component patterns.

## API and Data Rules

* Reuse the existing API client and feature API modules.
* Reuse existing React Query query keys, hooks, invalidation, and caching patterns.
* Do not fetch the same data through duplicate hooks or API calls.
* Keep TypeScript API types consistent with Laravel API Resources.
* When an API contract changes, update affected frontend types and consumers consistently.
* Laravel is the authoritative source of backend data.
* Do not duplicate backend business logic in the frontend.

## Component & UI Rules

* Reuse existing components before creating new ones.
* Follow established UI/UX patterns and styling conventions.
* Keep components focused and maintainable.
* Avoid unnecessary dependencies and abstractions.
* Do not introduce a new pattern when an existing project pattern already solves the problem.

## Change Safety

* Do not delete, rename, or replace existing components, routes, API functions, hooks, or features unless explicitly required by the current task and approved.
* Do not remove existing functionality because it appears unused or unrelated.
* Avoid unrelated refactoring.

## Validation

After frontend changes:

* Run the appropriate type checks, linting, tests, and build.
* Verify affected API interactions and UI flows.
* Confirm existing functionality remains intact.
