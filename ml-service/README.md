# AgroBenta ML service

Prototype CatBoost price-suggestion model for livestock sales.

> **Prototype only.** Training uses synthetic records. Its evaluation does not
> establish real-market price accuracy. Local model training and `chicken`
> support are proposed project decisions pending team/adviser approval and
> documentation updates. A private FastAPI service exists in `app.py`; no
> Laravel, Flutter, or Docker integration is implemented.

## Model scope

- One CatBoost Regressor for all five categories: `cattle`, `carabao`, `goat`,
  `swine`, `chicken`.
- Categorical features: `livestock_type`, `breed`, `sex`.
- Numerical features: `age_months`, `weight_kg`.
- Target: `actual_sale_price` in PHP.
- 20 supported category/breed combinations are defined in `features.py`.

## Installation

Python 3.11 is assumed (the checked-in `.venv` uses 3.11.9).

```powershell
cd ml-service
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

On macOS/Linux, activate with `source .venv/bin/activate`.

`requirements.txt` is UTF-8 and pins the existing dependency versions.

## Training

Default synthetic dataset:

```powershell
python train.py
```

Explicit dataset and provenance label:

```powershell
python train.py --dataset data/synthetic_livestock_sales.csv --provenance synthetic
```

Useful options:

```text
--dataset PATH          Training CSV
--provenance            synthetic | real (default: inferred from filename)
--seed                   Random seed (default: 42)
--test-fraction          Held-out fraction (default: 0.2)
--iterations             CatBoost iterations (default: 1000)
--depth                  Tree depth (default: 6)
--learning-rate          Learning rate (default: 0.05)
--l2-leaf-reg            L2 regularization (default: 3.0)
```

Training performs these steps:

1. Reads the CSV as UTF-8 (BOM accepted).
2. Validates the six required columns, supported category/breed pairs,
   `male`/`female`, positive numeric ranges, and peso-formatted prices.
3. Removes exact duplicate rows and reports the count.
4. Keeps repeated five-feature combinations with different prices.
5. Creates a reproducible 80/20 split stratified by breed as far as possible.
   Identical five-feature combinations always stay in one split.
6. Trains one CatBoost Regressor with native categorical handling. Direct-price
   MAE loss is used so the high-value cattle/carabao rows do not dominate the
   objective and underfit low-value chicken rows.
7. Compares it with a training-only median price-per-kg baseline by category.
8. Writes a versioned `.cbm` model and `reports/metrics.json`.

Outputs:

```text
models/catboost_price_v1_<UTC timestamp>.cbm
models/catboost_price_v1_<UTC timestamp>.metadata.json
reports/metrics.json
```

`reports/metrics.json` records the model version, timestamp, dataset filename,
SHA-256 hash, provenance, feature schema, supported categories/breeds,
train/test counts, duplicate counts, CatBoost parameters, held-out metrics, the
baseline comparison, and the synthetic-data warning.

The `.metadata.json` sidecar stores the training numeric ranges and observed
category/breed combinations. `predict.py` uses it to warn when an input is
outside the training distribution. It does not change the model.

## Prediction

By default, prediction loads the model named in `models/active_model.json`:

```powershell
python predict.py `
  --livestock-type cattle `
  --breed brahman `
  --sex male `
  --age-months 48 `
  --weight-kg 350
```

Example successful output:

```json
{
  "status": "ok",
  "predicted_price_php": 66708.05,
  "model_version": "v1",
  "model_sha256": "0971ccbaec34...",
  "provenance": "synthetic",
  "warnings": [],
  "reason_codes": [],
  "model": "models/catboost_price_v1_....cbm"
}
```

Unsafe input is withheld rather than priced:

```json
{
  "status": "withheld",
  "predicted_price_php": null,
  "warnings": ["age_months=0.098563 is outside the supported prototype envelope [1, 30]."],
  "reason_codes": ["outside_supported_age"],
  "model_version": "v1"
}
```

Select a registered candidate explicitly with `--model` or `MODEL_PATH`:

```powershell
python predict.py --model models/candidate_catboost_targeted_v3_20261105T133811927044Z.cbm `
  --livestock-type chicken --breed broiler --sex male `
  --age-months 0.098563 --weight-kg 0.5
```

Prediction never trains or retrains. The CLI exits `0` for `ok`/`warning`,
`2` for `withheld`, and `1` for invalid input or model/configuration errors.

## Validation and error analysis

```powershell
python evaluate.py
```

This reconstructs the Phase 2 split, loads v1, and writes:

```text
reports/error_analysis.json
reports/prediction_validation.json
```

It does not retrain or overwrite the model or `metrics.json`. It validates all
20 breed combinations, measures weight/age/sex/breed sensitivity, checks invalid
inputs, and confirms OOD warnings. Current v1 held-out findings:

- CatBoost MAE ₱3,075.07, RMSE ₱5,315.26, MAPE 10.88%.
- Baseline MAE ₱2,993.56, RMSE ₱5,161.97, MAPE 12.57%.
- Largest CatBoost MAE: cattle ₱7,094.23, carabao ₱6,838.38, swine ₱1,509.77.
- CatBoost beats the baseline on MAE for cattle, chicken, and goat; the baseline
  is better overall on MAE/RMSE and on carabao/swine.
- Carabao errors are mostly underprediction of high-value, heavy animals; swine
  errors are smaller but the baseline remains slightly better.
- Weight sensitivity is strong (correlations 0.95–0.996). Age sensitivity is
  weak or inconsistent for carabao and chicken. Sex changes move predictions by
  roughly 1.5–8.8% depending on category.
- All 20 breed combinations return positive predictions; all tested invalid
  inputs are rejected and all tested OOD inputs produce warnings.

## Controlled improvement

```powershell
python improve.py
```

The script keeps the Phase 2 test set untouched, splits the training pool into
train/validation, tries a small fixed parameter grid on validation only, selects
by validation MAE, refits the selected configuration on the full Phase 2
training pool, and evaluates once on the untouched test set. It writes
`reports/improvement_comparison.json`.

The selected validation candidate was `mae_d8_i1000_lr05_l2_3`. On the final
test it had MAE ₱3,068.06 (0.23% better than v1) but MAPE 11.83% (8.65% worse)
and chicken MAE 37.09% worse. That fails the documented replacement rule, so
**v1 is retained** and no v2 model is saved.

## Young-chicken extension

Generate the expanded dataset without modifying the original CSV:

```powershell
python generate_young_chicken_dataset.py
```

Outputs:

```text
data/synthetic_livestock_sales_v1_backup.csv   exact backup of the original
data/synthetic_livestock_sales_v2.csv          original 2,000 rows + 140 young rows
reports/young_chicken_dataset_manifest.json    assumptions and count breakdown
```

The 140 added records cover 30 rows at 1–7 days, 30 at 8–14 days, 40 at
15–21 days, and 40 at 22–30 days. All four chicken breeds have 35 records each
and both sexes are represented. Age is `days / 30.4375`, stored with six
decimals. Weights follow a documented breed-specific hatch-to-30-day curve;
prices are synthetic base-handling amounts plus weight-based rates. These are
prototype assumptions, not market quotes.

Train the candidate with the v1 hyperparameters, while holding out the original
Phase 2 test set and 40 young-chicken records:

```powershell
python train_young_chicken.py
```

Outputs:

```text
models/candidate_catboost_young_chicken_v2_<timestamp>.cbm
models/candidate_catboost_young_chicken_v2_<timestamp>.metadata.json
reports/young_chicken_training_v2.json
reports/young_chicken_prediction_validation_v2.json
```

The candidate filename deliberately does **not** match the default
`catboost_price_v*.cbm` pattern, so `predict.py` continues to use v1 unless the
candidate is requested explicitly with `--model`.

Current candidate results:

| Evaluation set | Candidate MAE | v1 MAE | Baseline MAE |
|---|---:|---:|---:|
| Original 400-row test | **2,968.61** | 3,075.07 | 2,993.56 |
| Young chicken 40-row test | **6.61** | 99.55 | 23.59 |
| Older chicken 80-row test | 55.32 | **48.49** | 80.72 |

The candidate improves the original test overall and young-chicken performance
substantially, but older-chicken MAE worsens by 14.09% and the category guard
fails. **v1 remains the default recommendation.** The candidate is retained only
as a young-chicken specialist for further review; it is not promoted solely
because its age predictions differ.

## Targeted v3 improvement

The Phase 4 v2 candidate improved young chickens but raised older-chicken MAE
from ₱48.49 to ₱55.32. Diagnosis is in `reports/v2_regression_analysis.json`:
the 100 added young rows shifted chicken predictions downward, especially for
12–24-month and boholano-native birds.

Validation-only experiments covered young/older sample weights, young-row
undersampling, and depth/iteration changes. The final selection uses
`reports/targeted_improvement_v3.json` plus one additional validation trial:

- Older chicken weight: **2.0**
- Young chicken weight: **1.05**
- Depth 6, 1,000 iterations, learning rate 0.05, L2 3.0
- Same expanded dataset and held-out splits; no records changed

Final candidate:

`models/candidate_catboost_targeted_v3_20261105T133811927044Z.cbm`

| Evaluation | v1 | v2 | v3 candidate |
|---|---:|---:|---:|
| Original 400 test MAE | 3,075.07 | **2,968.61** | 3,016.05 |
| Original 400 test RMSE | 5,315.26 | **5,151.34** | 5,174.10 |
| Original 400 test MAPE | 10.88% | **10.66%** | 10.37% |
| Older chicken 80 MAE | 48.49 | 55.32 | **46.37** |
| Young chicken 40 MAE | 99.55 | 6.61 | **6.14** |

Acceptance:

- Older chicken MAE ≤ ₱48.49: **PASS** (₱46.37)
- Young chicken MAE ≤ ₱7.27: **PASS** (₱6.14)
- Cattle/carabao/goat/swine within 5% of v2: **PASS**
- Overall original MAE not worse than v2: **FAIL** (₱3,016.05 vs ₱2,968.61,
  recorded as a secondary target)
- Candidate saved because the hard acceptance criteria passed. It is not
  promoted; `predict.py` still defaults to v1.

Reports:

```text
reports/v2_regression_analysis.json
reports/targeted_improvement_v3.json              (preserved completed search)
reports/targeted_improvement_v3_final.json
reports/targeted_prediction_validation_v3_final.json
```

## Model safety and deployment preparation

Run once to create the additive safety profiles and manifest:

```powershell
python prepare_deployment.py
```

It writes:

```text
models/<model>.safety.json
models/active_model.json
```

It never trains, deletes, overwrites, or promotes a model. The active model is
**v1**; v2 and v3 are listed as candidates.

### Safety rules

| Decision | Rule |
|---|---|
| Invalid | Unsupported category/breed, invalid sex, non-finite/zero/negative values, or age above 300 months |
| Withheld | Outside the category's observed min/max age or weight; far outside the observed age-bin weight support (two-fold margin); missing safety profile; non-positive model output |
| Warning | Inside the hard support envelope but outside the category/breed 1st–99th percentile or the age-band typical weight range; a price is returned |
| OK | Inside all hard and typical envelopes |

The category envelope is the observed training minimum/maximum per category.
Age-bin minimum/maximum values are **sparse synthetic training support, not
biological proof**: a twofold support margin allows plausible edge cases to
return a warning. Inputs far outside that support are withheld with
`insufficient_model_support`. These remain data-derived prototype guardrails,
not authoritative biological limits.

For example, a 1-month-old broiler at 0.5 kg is a warning (smaller than the
observed 1–3-month support floor), while a 3-day-old chicken at 500 kg is
withheld.

The 20 breed combinations are covered per model. v1 does not cover young
chickens below one month and withholds them; v3 covers the young age range.

### Active model and rollback

`models/active_model.json` contains the active entry, candidate entries, SHA-256
hashes, provenance, safety-profile filenames, and rollback metadata. To roll back
or select a candidate, change the `active` entry to a known registered candidate
and record the previous entry in `rollback`. Do not edit model filenames or
bypass the manifest. `MODEL_PATH` and `--model` provide explicit per-run
selection but do not promote a model.

### Prediction contract

The structured result contains:

```text
status                  ok | warning | withheld
predicted_price_php     number or null
model_version
model_sha256
provenance              synthetic
warnings
reason_codes
model_path
```

No confidence interval or min/max price is fabricated. Those require calibration
and a separate product decision before FastAPI/Laravel exposure.

## FastAPI service

The private API wraps the verified prediction pipeline. It loads and verifies
one model at startup; requests reuse that model and safety profile.

Start locally:

```powershell
cd ml-service
.\.venv\Scripts\Activate.ps1
python app.py
# or:
uvicorn app:app --host 127.0.0.1 --port 8002
```

The default bind is `127.0.0.1:8002`. No CORS or public exposure is configured.

### Docker deployment

The service is a private Compose service on `app_network`. It publishes no host
port; Laravel reaches it as `http://ml-service:8002`.

```powershell
cd C:\Roxy\Agrobenta
docker compose build ml-service
docker compose up -d ml-service
docker compose ps ml-service
docker compose logs --tail=50 ml-service

# Internal readiness check from the Laravel container
docker compose exec -T php php -r "echo file_get_contents('http://ml-service:8002/ready');"
```

The container runs Uvicorn on `0.0.0.0:8002` and has no public port mapping.

### Configuration

- Default: active model from `models/active_model.json` (currently v1).
- Explicit model: `--model` for the CLI, or `MODEL_PATH` for the API.
- Development v3 example:

```powershell
$env:MODEL_PATH = "models\candidate_catboost_targeted_v3_20261105T133811927044Z.cbm"
python app.py
```

The model file, metadata sidecar, safety profile, SHA-256, and manifest entry are
verified at startup. A missing, corrupt, or unregistered model leaves the service
running but not ready.

### Endpoints

| Method | Path | Response |
|---|---|---|
| `GET` | `/health` | Process liveness |
| `GET` | `/ready` | 200 with contract version, active model version/hash/provenance, or 503 |
| `POST` | `/v1/predict` | Versioned contract: 200 prediction; 422 invalid/withheld; 503 unavailable; 500 unexpected |
| `POST` | `/predict` | Backward-compatible alias of `/v1/predict` |

Request:

```json
{
  "livestock_type": "cattle",
  "breed": "brahman",
  "sex": "male",
  "age_months": 48,
  "weight_kg": 350
}
```

Successful response:

```json
{
  "contract_version": "1.0",
  "status": "ok",
  "predicted_price_php": 66708.05,
  "model_version": "v1",
  "model_sha256": "0971cc...",
  "provenance": "synthetic",
  "warnings": [],
  "reason_codes": []
}
```

Withheld response (`422`):

```json
{
  "contract_version": "1.0",
  "status": "withheld",
  "predicted_price_php": null,
  "model_version": "v3-targeted",
  "model_sha256": "ab80c6...",
  "provenance": "synthetic",
  "warnings": ["weight_kg=500 is outside the supported prototype envelope [0.03, 4]."],
  "reason_codes": ["outside_supported_weight"]
}
```

PowerShell examples:

```powershell
# Health/readiness
Invoke-RestMethod http://127.0.0.1:8002/health
Invoke-RestMethod http://127.0.0.1:8002/ready

# Versioned prediction
Invoke-RestMethod -Method Post `
  -Uri http://127.0.0.1:8002/v1/predict `
  -ContentType 'application/json' `
  -Body '{"livestock_type":"cattle","breed":"brahman","sex":"male","age_months":48,"weight_kg":350}'
```

The API returns no model file paths, confidence intervals, or min/max prices.
Laravel must map `422` invalid/withheld, `503` unavailable, and `500` unexpected
errors without retrying unsafe requests automatically.

### Laravel endpoint

The seller-facing endpoint is:

```text
POST /api/seller/listings/{listing}/price-suggestion
```

It is authenticated, seller-only, owner-only, and draft-only. It reads the
listing's persisted livestock attributes, converts units to months/kilograms,
and returns a point estimate. `asking_price` and listing status are never
changed. Successful `ok`/`warning` estimates are persisted; `422` withheld or
invalid results are not. `estimated_min` and `estimated_max` are null.

Example success (`200`):

```json
{
  "success": true,
  "message": "Price suggestion generated.",
  "data": {
    "listing_id": 12,
    "estimated_min": null,
    "estimated_max": null,
    "estimated_value": "50000.55",
    "status": "ok",
    "warnings": [],
    "reason_codes": [],
    "provenance": "synthetic",
    "model_version": "v1",
    "input_snapshot": {
      "livestock_type": "cattle",
      "breed": "brahman_cross",
      "sex": "male",
      "age_months": 24,
      "weight_kg": 498.9516
    }
  }
}
```

## Tests

```powershell
python -m unittest discover -s tests -t . -v
```

Coverage includes peso parsing, dataset validation, duplicate handling,
leakage-safe splitting, model loading without retraining, prediction input
validation, OOD profile warnings, evaluation metrics, the tuning decision rule,
young-chicken generation distribution, fractional ages, the young-chicken
leakage-safe split, sample-weight strategies, undersampling, targeted
acceptance/selection logic, category/breed safety envelopes, joint age-weight
withholding, active-manifest selection, missing metadata/safety files, checksum
mismatch, `MODEL_PATH` candidate selection, FastAPI health/readiness, all five
categories and 20 breed combinations, fractional young-chicken ages, warnings,
withheld predictions, invalid API input, and startup model failure.

## Data files

`data/synthetic_livestock_sales.csv` is the prototype training file.
`data/livestock_sales.csv` is a placeholder for future genuine sales data and
currently contains only its header.

`ml-service/.gitignore` ignores `data/*.csv`, so these datasets are not tracked.
A clean checkout needs the data supplied separately or a deterministic
generation process. Do not commit private real sales data.

## Limitations

- Synthetic metrics are not evidence of real-world accuracy.
- The Laravel enum, API catalog, and mobile client now expose `chicken` as a
  supported category. The functional documentation still lists four categories;
  that documentation conflict remains tracked separately.
- A single regressor returns one point estimate. The Laravel
  `ai_price_estimates` contract also has `estimated_min` / `estimated_max`
  fields; a range policy is still required before API integration.
- Breed is free text in the application. Prediction normalizes labels, but
  unseen or differently spelled breeds are rejected rather than guessed.
- v1 remains the recommended general/default model. The Phase 4 young-chicken
  candidate regressed older-chicken MAE. The v3 targeted candidate fixes that
  regression and passes the hard acceptance criteria, but its overall original
  test MAE is slightly worse than v2, so it is a specialist candidate rather
  than an automatic replacement.
- Age and sex effects are learned from synthetic data and are not verified
  market relationships. Young-chicken weights and prices are documented
  synthetic assumptions, not verified market data.
- The v3 candidate uses the v2 training pool and simulated sample weights; no
  records were fabricated or changed.
- Safety envelopes are derived from synthetic training minima/maxima and
  percentiles. They are prototype guardrails, not biological or veterinary
  authority. Age-bin support margins are explicitly model-coverage limits, not
  biological determinations.
- No confidence interval or min/max price is produced. That requires
  calibration and an approved contract decision.
- `predict.py` still defaults to v1 through the active manifest. v3 is not
  promoted; `MODEL_PATH`/`--model` only select it explicitly.
- The FastAPI service is private and has no authentication layer. It must stay
  on localhost/private networking until Laravel integration defines auth and
  network policy.
- No Laravel, Flutter, or Docker integration is implemented here.
