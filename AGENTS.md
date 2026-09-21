# AGENTS.md

## Project Purpose

This repository is a **generic, reusable full-stack starter template**.

It must remain project-agnostic and should be usable as the foundation for different applications.

### Stack

* Laravel 13 — Backend
* React + Vite — Frontend
* MySQL — Database
* Redis — Cache/queue support
* Nginx — Web server/reverse proxy
* Supervisor — Process management
* Docker / Docker Compose — Development environment

---

## Core Rules

1. **Inspect before modifying.**

   * Read relevant documentation and existing code before making changes.
   * Never assume the current implementation.

2. **Follow project instructions.**

   * Read this root `AGENTS.md`.
   * Read any applicable `SUBAGENTS.md` before modifying files in its scope.

3. **Keep the template generic.**

   * No FarmLink-specific terminology, business rules, roles, workflows, or data.
   * Avoid assumptions about the future project's domain.

4. **Prefer simple, maintainable solutions.**

   * Do not overengineer.
   * Avoid unnecessary packages, abstractions, services, or configuration.
   * Reuse existing architecture when practical.

5. **Preserve working infrastructure.**

   * Do not change Docker architecture or existing configuration unless necessary.
   * Explain significant architectural changes before implementing them.

6. **Security first.**

   * Never hardcode secrets, passwords, API keys, or tokens.
   * Never commit real credentials.
   * Validate and sanitize external input.
   * Use framework security features instead of custom security implementations whenever possible.
   * Do not weaken authentication, authorization, CORS, CSRF, or other security protections merely to make development easier.

7. **Keep configuration portable.**

   * Project-specific values belong in environment configuration.
   * Use clear `CHANGE_THIS_*` placeholders where user configuration is required.
   * Do not hardcode machine-specific paths or settings.

8. **Avoid unrelated changes.**

   * Modify only what is necessary for the requested task.
   * Do not silently refactor unrelated code.
   * Do not implement future phases early.

9. **Validate every change.**

   * Run appropriate tests, linting, builds, configuration validation, or Docker checks.
   * Fix issues introduced by your changes before reporting completion.

10. **Keep documentation accurate.**

    * Update documentation when behavior, setup, commands, or architecture changes.
    * Do not leave project-specific or outdated instructions behind.

---

## Development Guardrails

### Do

* Follow Laravel and React conventions.
* Prefer existing framework functionality.
* Keep APIs predictable and consistent.
* Keep frontend/backend responsibilities clear.
* Use meaningful names.
* Make small, focused changes.
* Explain important trade-offs when necessary.

### Do Not

* Add features that were not requested.
* Introduce unnecessary dependencies.
* Duplicate existing functionality.
* Hardcode project-specific assumptions.
* Store secrets in source control.
* Modify unrelated files for convenience.
* Claim something works without validating it.
  Never delete, rename, or remove existing files, routes, features, or code unless it is explicitly required by the current task and approved by the user.
  Never assume something is obsolete just because it is unused, incomplete, or unrelated to the current phase.
  If deletion appears necessary, stop and ask for explicit approval first.

---

## Git Safety

* Do not create commits unless explicitly requested.
* Do not push to a remote repository unless explicitly requested.
* Do not reset, rebase, force-push, or delete branches without explicit approval.
* Never discard existing user changes.
* Before modifying files with existing uncommitted changes, inspect their state and avoid overwriting user work.

---

## Phase Discipline

The project may be developed in defined phases.

When a specific phase is requested:

* Implement **only that phase**.
* Do not implement later phases.
* Preserve compatibility with planned future phases.
* Validate the completed phase.
* Report:

  * Files changed
  * What was implemented
  * Validation performed
  * Any remaining issues or decisions

---

## Completion Standard

A task is complete only when:

1. The requested functionality is implemented.
2. Existing functionality is not unnecessarily broken.
3. Relevant validation has passed.
4. No unnecessary project-specific code was introduced.
5. Documentation is updated when required.
6. The final report clearly states what changed and what was verified.

## Visual Design Source of Truth

`DESIGN.md` is the visual design source of truth for the AgroBenta frontend.

Before implementing or modifying any frontend screen, read `DESIGN.md` and
follow its typography, spacing, color, component, navigation, and visual rules.

The administrator prototype is the primary visual reference.

Do not introduce a different visual style unless explicitly instructed.

Do not make the interface look like a generic AI-generated SaaS dashboard.

Maintain a practical, professional, restrained administrative-system design.
