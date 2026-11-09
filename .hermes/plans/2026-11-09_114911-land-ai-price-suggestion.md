# Plan — Land the AI livestock price suggestion feature (GAP-10)

> **Assumption.** `/plan` was invoked with no task text and the conversation had no
> prior context. A clarifying question was asked and timed out unanswered, so this
> plan covers the strongest thread of in-flight work found in the repository:
> merging `origin/feature/ai-price-suggestion` into `main`. If that is not the
> intended task, stop here and say so — the other threads found are listed under
> "Other threads considered" at the end.

---

## Goal

Merge the already-implemented AI price suggestion feature
(`origin/feature/ai-price-suggestion`, 3 commits, 97 files) into `main`, after
verifying the backend, ML-service and mobile suites pass against current `main`
(`2783292`).

## Current context / assumptions

Verified facts (read-only inspection, 2026-11-09):

* `main` is at `2783292`, working tree clean, `main` == `origin/main`
  (`git rev-list --left-right --count main...origin/main` → `0	0`).
* `origin/feature/ai-price-suggestion` is at `361b751` (2026-11-07 23:21 +0800).
  Its 3 commits are:
  * `c7ee786` `chore(ml): initialize CatBoost ML service structure`
  * `b8b5d39` `feat: implement AI livestock price suggestion`
  * `361b751` `Merge latest main into AI price suggestion feature`
* The branch **already contains `main`**: `git merge-base main 361b751` →
  `27832928e774d1a7d40f91074a374300889cf1e1` (main's tip). So
  `git rev-list --left-right --count main...361b751` → `0	3`.
* **No pull request exists** for this branch (GitHub API
  `GET /repos/roxcy1/AgroBenta/pulls?head=roxcy1:feature/ai-price-suggestion&state=all`
  → `[]`), and the branch is not merged into `main`.
* Branch contents:
  * `ml-service/` — FastAPI + CatBoost service: `app.py`, `predict.py`,
    `model_registry.py`, `features.py`, `validation.py`, `evaluate.py`,
    `train.py`, `train_young_chicken.py`, `tune_targeted_v3.py`, `prepare_deployment.py`,
    `finalize_targeted_v3.py`, `improve.py`, `diagnose_v2_regression.py`,
    `generate_young_chicken_dataset.py`, `Dockerfile`, `requirements.txt`,
    `models/active_model.json` + 3 committed `.cbm` model binaries,
    and `tests/` (12 `test_*.py` modules).
  * `backend/` — `app/Contracts/PriceSuggestionProvider.php`,
    `app/Data/PriceSuggestionInput.php`, `app/Data/PriceSuggestionResult.php`,
    `app/Enums/LivestockType.php`, `app/Exceptions/PriceSuggestionRejected.php`,
    `app/Exceptions/PriceSuggestionUnavailable.php`,
    `app/Http/Controllers/Api/SellerListing/PriceSuggestionController.php`,
    `app/Http/Resources/AiPriceEstimateResource.php`,
    `app/Repositories/PriceSuggestion/AiPriceEstimateRepository.php`,
    `app/Services/PriceSuggestion/{FastApiPriceSuggestionProvider,PriceSuggestionService}.php`,
    `app/Support/PriceSuggestion/BreedNormalizer.php`,
    `config/services.php`, one migration, `routes/api.php`,
    `tests/Feature/SellerListing/PriceSuggestionTest.php` (15 tests),
    and a new safe-database guard in `tests/TestCase.php`.
  * `mobile/` — `lib/models/ai_price_estimate.dart`,
    `lib/features/seller_listings/view/seller_listing_form_screen.dart`,
    `lib/services/seller_listing_service.dart`,
    `lib/repositories/seller_listing_repository.dart`,
    `lib/core/network/{api_client,api_exception}.dart`,
    `lib/core/constants/api_constants.dart`, plus tests; `mobile/AGENTS.md`
    GAP-10 flipped to `CLOSED`.
  * `compose.yaml` — new private `ml-service` service on `app_network`, **no host
    port published**; `php` gains `PRICE_PREDICTION_URL=http://ml-service:8002`
    and depends on `ml-service` being healthy.
  * `.env.example`, `backend/.env.example`, `.gitignore`,
    `docs/MOBILE_API_CONTRACT_PROPOSAL.md`.
* Host tooling: Docker 29.4.2 + Compose v5.1.3 present; the AgroBenta stack is
  **not** currently running (only the DisasterAid stack is up). Flutter 3.47.4
  present. Python 3.14.9 + pytest 9.1.1 present, but **`catboost` is not
  installed on the host** — ML-service tests must run in Docker or a venv.
* No CI exists: `.github/workflows/` does not exist. All verification is manual.

## Architecture / proposed approach

The feature is implemented and committed; this is a **verify → fix → merge**
job, not a rewrite. Check out the branch, run the three suites, fix only what is
actually broken (on the branch), then open a PR and merge. Do not restructure
the feature, do not add the buyer-facing estimate, and do not invent a range
policy — both are explicitly out of scope for this phase.

---

## Step-by-step tasks

### Task 0 — Baseline `main` before touching the branch

Establish that `main` is green so a pre-existing failure is not later blamed on
the branch.

```sh
cd /c/Users/Argie Cabudbud/AgroBenta
git status --porcelain          # expected: no output
git rev-parse --short HEAD      # expected: 2783292
cd mobile
flutter pub get
flutter analyze                 # expected: "No issues found!"
flutter test                    # expected: all tests pass
```

Record the test totals. If `flutter analyze` or `flutter test` already fails on
`main`, **stop and report** — do not proceed until the baseline is understood.

---

### Task 1 — Check out the feature branch

```sh
cd /c/Users/Argie Cabudbud/AgroBenta
git fetch origin
git switch --track origin/feature/ai-price-suggestion
```

Verify:

```sh
git rev-list --left-right --count main...HEAD   # expected: 0	3
git status --porcelain                          # expected: no output
git log --oneline -3
# expected:
#   361b751 Merge latest main into AI price suggestion feature
#   b8b5d39 feat: implement AI livestock price suggestion
#   c7ee786 chore(ml): initialize CatBoost ML service structure
```

---

### Task 2 — Backend suite (Docker)

The backend tests run on `sqlite :memory:` (`backend/phpunit.xml`), so no MySQL
data is touched. `tests/TestCase.php` now refuses to run against any other
database.

```sh
cd /c/Users/Argie Cabudbud/AgroBenta
docker compose up -d php mysql redis
docker compose exec php composer test
```

`composer test` runs `php artisan config:clear` then `php artisan test`.

**Expected:** every Unit and Feature test passes — 0 failures, 0 errors,
0 risky. `Tests\Feature\SellerListing\PriceSuggestionTest` must run its 15 tests:

```
success_converts_units_normalizes_breed_and_persists
warning_is_returned_and_persisted
withheld_response_is_422_and_not_persisted
missing_required_listing_inputs_are_422_without_provider_call
unsupported_breed_is_422_without_provider_call
day_and_kg_conversion_are_sent_canonically
young_chicken_inputs_are_sent_canonically
another_sellers_listing_is_404
buyer_is_forbidden
unauthenticated_request_is_401
active_listing_is_422
provider_unavailable_is_safe_503
provider_timeout_is_safe_503
malformed_or_incompatible_provider_response_is_503
```

(That is 14 names visible in the file plus the class-level set; the runner will
report the exact count. What matters is that the class runs and passes.)

If the `php` image is stale, run `docker compose build php` first.

**If a test fails:** read the failure, determine whether it is a genuine defect
in the branch or an environment problem, and fix it on the branch (Task 6).

---

### Task 3 — ML-service suite (Docker — host lacks `catboost`)

```sh
cd /c/Users/Argie Cabudbud/AgroBenta
docker compose build ml-service
docker compose run --rm --no-deps ml-service python -m unittest discover -s tests -t . -v
```

**Expected:** all tests in `ml-service/tests/` pass (0 failures, 0 errors).
Coverage per `ml-service/README.md` §Tests: peso parsing, dataset validation,
duplicate handling, leakage-safe splitting, model loading without retraining,
prediction input validation, OOD profile warnings, evaluation metrics, the
tuning decision rule, young-chicken generation, fractional ages, sample-weight
strategies, undersampling, targeted acceptance/selection, category/breed safety
envelopes, joint age/weight withholding, active-manifest selection, missing
metadata/safety files, checksum mismatch, `MODEL_PATH` candidate selection,
FastAPI health/readiness, all five categories and 20 breed combinations,
warnings, withheld predictions, invalid API input, startup model failure.

Fallback if the Docker build cannot run (no network for pip/apt):

```sh
cd /c/Users/Argie Cabudbud/AgroBenta/ml-service
python -m venv .venv
./.venv/Scripts/python -m pip install -r requirements.txt
./.venv/Scripts/python -m unittest discover -s tests -t . -v
```

(`.venv/` is already gitignored by the branch's `.gitignore`.)

---

### Task 4 — Mobile suite

```sh
cd /c/Users/Argie Cabudbud/AgroBenta/mobile
flutter pub get
flutter analyze        # expected: "No issues found!"
flutter test           # expected: all tests pass
```

Must include and pass:

* `test/models/ai_price_estimate_test.dart`
* `test/features/seller_listings/seller_listing_form_screen_test.dart`
* `test/features/seller_listings/seller_listing_controller_test.dart`
* `test/services/seller_listing_service_test.dart`
* `test/core/network/api_client_test.dart`

**If a test fails:** same rule as Task 2 — diagnose, then fix on the branch.

---

### Task 5 — Focused security/contract review of the new surface

Read these four files and confirm each claim; report anything that does not hold:

1. `backend/routes/api.php` — the new route is
   `POST /api/seller/listings/{listing}/price-suggestion`, inside the
   `auth:sanctum` + `ability:mobile` + seller-capability group, with
   `->whereNumber('listing')`.
2. `backend/app/Http/Controllers/Api/SellerListing/PriceSuggestionController.php`
   — owner-scoped via `SellerListingService::findOwnedForSeller`, `404` for a
   non-owner, accepts **no request body**, never writes `asking_price`, never
   changes listing status.
3. `backend/app/Services/PriceSuggestion/PriceSuggestionService.php` —
   draft-only, maps provider rejections to `422` and unavailability to `503`,
   persists `ok`/`warning` estimates only.
4. `compose.yaml` — `ml-service` publishes **no** `ports:` entry and is reachable
   only as `http://ml-service:8002` on `app_network`.

Do not change code here; this task produces a list of confirmed facts (or
defects) for the PR description.

---

### Task 6 — Fix what verification found

Fix only real defects, on the branch, one commit per defect. For any behaviour
change, follow the TDD cycle: write the failing test first, run it to see it
fail, implement minimally, run it to see it pass.

Known candidates to check (verify — do not assume):

* **Ignored-but-tracked training data.** `ml-service/.gitignore` contains
  `data/*.csv` and `ml-service/README.md` §Data files says "these datasets are
  not tracked", yet `git ls-tree -r 361b751 -- ml-service/data/` shows
  `synthetic_livestock_sales.csv` (95,265 B) and `synthetic_livestock_sales_v2.csv`
  (102,214 B) **are** tracked. Decide deliberately: either `git rm --cached` both
  files (and confirm the service still builds without them) or correct the
  README. Report the contradiction either way.
* **Range policy.** `ml-service/README.md` §Limitations states a range policy is
  still required; `estimated_min` / `estimated_max` are always null and the
  mobile model treats them as nullable. Confirm the mobile UI never renders an
  invented range.
* **Category documentation conflict.** The branch adds `chicken` to
  `backend/app/Enums/LivestockType.php`, the API catalog and the mobile client.
  `docs/AGROBENTA_FUNCTIONAL_DOCUMENTATION.md` still lists four categories.
  Per `docs/AGENTS.md`, this is a defect to **report to the manuscript owner**,
  not something to fix by editing the functional document.

Commit each fix:

```sh
git add <exact paths>
git commit -m "<type>(<scope>): <imperative summary>"
```

---

### Task 7 — Push

```sh
git push origin feature/ai-price-suggestion
```

Expected: either "Everything up-to-date" (no fixes were needed) or the new
commits are accepted.

---

### Task 8 — Open the PR and merge

1. Open a PR from `feature/ai-price-suggestion` into `main` on
   `https://github.com/roxcy1/AgroBenta`.
2. PR description must state:
   * what the feature is (seller-side, draft-only price decision support);
   * the endpoint contract (`POST /api/seller/listings/{listing}/price-suggestion`,
     no body, owner-scoped, never writes `asking_price` or status);
   * the new private `ml-service` container and its network boundary;
   * the security review results from Task 5;
   * known limitations (point estimate only, synthetic training data, chicken
     category documentation conflict).
3. Merge with a **merge commit** — this repository's history uses them
   (e.g. `Merge pull request #54 from roxcy1/feature/trinidad-location-and-bugfixes`).
4. Confirm and clean up locally:

   ```sh
   git switch main
   git pull origin main
   git log --oneline -3          # expected: the merge commit on top
   ```

5. Post-merge smoke test:

   ```sh
   docker compose up -d
   curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8001/healthz   # expected: 200
   docker compose exec php curl -s http://ml-service:8002/health           # expected: {"status":"ok", ...}
   docker compose exec php php artisan route:list --path=api/seller/listings
   # expected: a line containing POST .../price-suggestion
   ```

---

## Tests / validation summary

| Suite | Command | Expected |
|---|---|---|
| Backend | `docker compose exec php composer test` | 0 failures, 0 errors; `PriceSuggestionTest` runs |
| ML service | `docker compose run --rm --no-deps ml-service python -m unittest discover -s tests -t . -v` | 0 failures, 0 errors |
| Mobile | `cd mobile && flutter analyze && flutter test` | "No issues found!"; all tests pass |
| Route registration | `docker compose exec php php artisan route:list --path=api/seller/listings` | `POST .../price-suggestion` present |
| Service health | `docker compose exec php curl -s http://ml-service:8002/health` | `{"status":"ok", ...}` |

A task is done only when the relevant row is green and the exact commands above
were actually run. Never report a suite as passing without its output.

---

## Risks, tradeoffs, and open questions

* **The task is an assumption.** `/plan` carried no task and the clarifying
  question timed out. If the intent was one of the other threads below, this plan
  is the wrong one.
* **Model binaries in git.** Three `.cbm` files (~1.1 MB each) are committed.
  Acceptable for a prototype, but they will only grow; consider Git LFS before
  adding v4+.
* **Synthetic training data.** `ml-service/README.md` §Limitations is explicit
  that synthetic metrics are not evidence of real-world accuracy. The project
  owner must accept this for the capstone; do not present the numbers as
  validation.
* **No range policy.** `estimated_min` / `estimated_max` are always null. The
  mobile UI must not invent a range, and the API contract must not promise one.
* **Documentation conflict (chicken category).** Report to the manuscript owner
  per `docs/AGENTS.md`; do not silently edit the functional documentation.
* **No CI.** Nothing runs automatically on push; the three suites are the only
  gate. Consider adding a GitHub Actions workflow as a follow-up.
* **Docker build needs network.** `ml-service` installs `libgomp1` via apt and
  ~35 Python packages via pip; the image is not cached on this host.
* **Merge method.** The plan assumes a merge commit and a PR. If the owner
  prefers rebase or a direct fast-forward, adjust Task 8.
* **Scope discipline.** Do not add the buyer-facing reference price
  (functional documentation §5.1) and do not design a range policy in this task;
  both are explicitly still open.

## Other threads considered (not planned)

* `stash@{0}` — "WIP: listing photos additional fixes" on
  `feature/listing_photos_mobile-gaps`. It conflicts with `main`
  (`git stash show -p stash@{0} | git apply --check` → conflicts in both files)
  and `main`'s `listing_photo_grid.dart` is already strictly more advanced
  (retry/failed overlay, `PlatformException` handling, `LocalImagePreview`), so
  the stash would regress it.
* Stale branch `feature/listing_photos_mobile-gaps` (`e8c88c4`, 9 commits, all
  patch-equivalent to work already in `main` via PRs #52/#53) plus
  `stash@{1..4}`.
* Untracked `mobile/.widget_preview/` — Flutter/Android Studio preview build
  output, not gitignored. Trivial `.gitignore` addition.
