# Documentation — Agent Instructions

## Scope

This file applies to `docs/`.

## What lives here

Approved **project-level** documentation — business and functional rules that
span more than one application in this repository.

| File | Contents |
|---|---|
| `AGROBENTA_FUNCTIONAL_DOCUMENTATION.md` | The approved AgroBenta functional/system documentation. Source of truth for business rules. |
| `MOBILE_API_CONTRACT_PROPOSAL.md` | A **proposal** for the mobile API. Not implemented, not agreed. |

## Rules

* `AGROBENTA_FUNCTIONAL_DOCUMENTATION.md` is **approved**. Do not edit it to
  resolve a disagreement, and do not use it as a scratchpad. If it is wrong or
  incomplete, report that — do not amend it.
* Business rules come from the approved functional documentation, in the
  source-of-truth order set by the root `AGENTS.md`.
* Do not invent business rules. Do not silently change approved terminology. If
  a rule is genuinely unclear, report it instead of writing something plausible.
* `MOBILE_API_CONTRACT_PROPOSAL.md` is a **proposal under review**. Nothing may
  be implemented — in `backend/` or in `mobile/` — against it until it is
  approved. Laravel is authoritative over any document, including this one.
* Technical contracts are verified against the actual implementation. Where a
  document and the code disagree, the code describes what the system does and
  the document describes what it should do. Both facts get reported; neither
  gets silently changed.
