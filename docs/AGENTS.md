# Documentation — Agent Instructions

## Scope

This file applies to `docs/`.

## What lives here

**Project-level** documentation — business and functional rules that span more
than one application in this repository.

| File | Contents |
|---|---|
| `AGROBENTA_FUNCTIONAL_DOCUMENTATION.md` | The AgroBenta functional/system rules, **aligned to the capstone manuscript**. Each rule cites its manuscript page; open questions are in §13. |
| `MOBILE_API_CONTRACT_PROPOSAL.md` | A **proposal** for the mobile API. Not authoritative. |

## Source of truth

The **capstone manuscript** (PDF, kept outside the repository) is the final
document. `AGROBENTA_FUNCTIONAL_DOCUMENTATION.md` restates it for the
repository. See "Business Rules Source of Truth" in the root `AGENTS.md`.

## Rules

* Business rules come from the manuscript, as restated in
  `AGROBENTA_FUNCTIONAL_DOCUMENTATION.md`.
* **Edit `AGROBENTA_FUNCTIONAL_DOCUMENTATION.md` only to make it match the
  manuscript** (or when the project manager approves a change). Cite the
  manuscript page or figure for every rule you add or change, and add an entry
  to its change log (§15).
* Do not edit it to match the code. If the code differs from the document,
  report the code as a defect.
* Where the manuscript is silent or contradicts itself, do not write something
  plausible. Add the question to §13 of the functional documentation and
  report it.
* Do not invent business rules. Do not silently change terminology (§0.3 of the
  functional documentation lists it).
* `MOBILE_API_CONTRACT_PROPOSAL.md` is a **proposal**. It never overrides the
  manuscript or the functional documentation. Laravel is authoritative over it
  for what the API currently does.
* Technical contracts are verified against the actual implementation. Where a
  document and the code disagree, the code describes what the system does and
  the document describes what it should do. Both facts get reported; neither
  gets silently changed.
