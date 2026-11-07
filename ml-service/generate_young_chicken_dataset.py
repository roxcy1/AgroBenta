"""Generate 140 synthetic young-chicken rows and append them to a v2 CSV.

Assumptions (prototype only, not verified market prices)
--------------------------------------------------------
- Age is recorded as fractional months using ``days / 30.4375``. No rounding
  to whole months is applied.
- Weight follows a simple breed-specific growth curve from hatch weight to an
  assumed 30-day weight. Male birds are 3% heavier and female birds 3% lighter
  than the curve, with a small deterministic jitter.
- Price is a synthetic per-bird amount built from a small handling/base amount
  plus weight times a breed-specific synthetic price-per-kg rate, with a small
  deterministic jitter. It is not a market quote.
- The four supported chicken breeds and both sexes are represented in every
  age band.
- The original CSV is read-only; the expanded CSV is written separately.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import random
import shutil
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"
REPORTS_DIR = BASE_DIR / "reports"
DEFAULT_SOURCE = DATA_DIR / "synthetic_livestock_sales.csv"
DEFAULT_OUTPUT = DATA_DIR / "synthetic_livestock_sales_v2.csv"
BACKUP_PATH = DATA_DIR / "synthetic_livestock_sales_v1_backup.csv"
MANIFEST_PATH = REPORTS_DIR / "young_chicken_dataset_manifest.json"

DEFAULT_SEED = 20261105
DAYS_PER_MONTH = 30.4375

AGE_BANDS: tuple[tuple[str, int, int, int], ...] = (
    ("1-7_days", 1, 7, 30),
    ("8-14_days", 8, 14, 30),
    ("15-21_days", 15, 21, 40),
    ("22-30_days", 22, 30, 40),
)

# Each breed receives 35 records. Column sums are 30, 30, 40, 40.
BREED_ALLOCATION: dict[str, tuple[int, int, int, int]] = {
    "broiler": (8, 7, 10, 10),
    "layer": (7, 8, 10, 10),
    "improved_native_chicken": (8, 7, 10, 10),
    "boholano_native_chicken": (7, 8, 10, 10),
}

BREED_GROWTH: dict[str, dict[str, float]] = {
    # hatch kg, assumed 30-day kg, growth-curve exponent, base head PHP,
    # synthetic PHP/kg rate.
    "broiler": {
        "hatch_kg": 0.042,
        "target_30d_kg": 1.45,
        "exponent": 1.55,
        "base_head_php": 26.0,
        "price_per_kg_php": 160.0,
    },
    "layer": {
        "hatch_kg": 0.034,
        "target_30d_kg": 0.28,
        "exponent": 1.20,
        "base_head_php": 24.0,
        "price_per_kg_php": 134.0,
    },
    "improved_native_chicken": {
        "hatch_kg": 0.033,
        "target_30d_kg": 0.34,
        "exponent": 1.25,
        "base_head_php": 28.0,
        "price_per_kg_php": 211.0,
    },
    "boholano_native_chicken": {
        "hatch_kg": 0.030,
        "target_30d_kg": 0.24,
        "exponent": 1.20,
        "base_head_php": 26.0,
        "price_per_kg_php": 232.0,
    },
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _age_days_pool(start: int, end: int, count: int, rng: random.Random) -> list[int]:
    days = list(range(start, end + 1))
    pool: list[int] = []
    while len(pool) < count:
        pool.extend(days)
    pool = pool[:count]
    rng.shuffle(pool)
    return pool


def curve_weight_kg(breed: str, day: int, sex: str) -> float:
    """Deterministic growth-curve weight, before the generation jitter."""
    growth = BREED_GROWTH[breed]
    progress = (day / 30.0) ** growth["exponent"]
    base = growth["hatch_kg"] + (
        growth["target_30d_kg"] - growth["hatch_kg"]
    ) * progress
    sex_factor = 1.03 if sex == "male" else 0.97
    return base * sex_factor


def _weight_kg(breed: str, day: int, sex: str, rng: random.Random) -> float:
    jitter = rng.uniform(0.95, 1.05)
    return curve_weight_kg(breed, day, sex) * jitter


def _price_php(
    breed: str,
    weight_kg: float,
    rng: random.Random,
) -> float:
    growth = BREED_GROWTH[breed]
    base = growth["base_head_php"] + weight_kg * growth["price_per_kg_php"]
    jitter = rng.uniform(0.92, 1.08)
    return max(25.0, base * jitter)


def generate_rows(seed: int = DEFAULT_SEED) -> list[dict[str, Any]]:
    """Generate exactly 140 unique young-chicken rows."""
    rng = random.Random(seed)
    rows: list[dict[str, Any]] = []
    seen: set[tuple[Any, ...]] = set()

    for band_index, (band_name, start, end, count) in enumerate(AGE_BANDS):
        days = _age_days_pool(start, end, count, rng)
        breed_day_cursor = 0

        for breed in BREED_ALLOCATION:
            breed_count = BREED_ALLOCATION[breed][band_index]
            for breed_offset in range(breed_count):
                day = days[breed_day_cursor % len(days)]
                breed_day_cursor += 1
                sex = "male" if breed_offset % 2 == 0 else "female"

                for _ in range(100):
                    weight = _weight_kg(breed, day, sex, rng)
                    price = _price_php(breed, weight, rng)
                    age_months = round(day / DAYS_PER_MONTH, 6)
                    row = {
                        "livestock_type": "chicken",
                        "breed": breed,
                        "sex": sex,
                        "age_months": age_months,
                        "weight_kg": round(weight, 2),
                        "actual_sale_price": f"\u20b1{round(price):,}",
                        "age_days": day,
                        "age_band": band_name,
                    }
                    key = (
                        row["livestock_type"],
                        row["breed"],
                        row["sex"],
                        row["age_months"],
                        row["weight_kg"],
                        row["actual_sale_price"],
                    )
                    if key not in seen:
                        seen.add(key)
                        rows.append(row)
                        break
                else:
                    raise RuntimeError(
                        f"Could not generate a unique row for {breed} day {day}."
                    )

    if len(rows) != 140:
        raise RuntimeError(f"Expected 140 rows, generated {len(rows)}.")
    if len(seen) != 140:
        raise RuntimeError("Generated rows contain exact duplicates.")

    return rows


def _newline_for(payload: bytes) -> bytes:
    return b"\r\n" if b"\r\n" in payload[:4096] else b"\n"


def _csv_rows_bytes(rows: list[dict[str, Any]], newline: bytes) -> bytes:
    buffer = io.StringIO()
    writer = csv.writer(buffer, lineterminator=newline.decode("ascii"))
    for row in rows:
        writer.writerow(
            [
                row["livestock_type"],
                row["breed"],
                row["sex"],
                f"{row['age_months']:.6f}",
                f"{row['weight_kg']:.2f}",
                row["actual_sale_price"],
            ]
        )
    return buffer.getvalue().encode("utf-8")


def build_output(
    source: Path,
    output: Path,
    seed: int = DEFAULT_SEED,
) -> dict[str, Any]:
    if not source.is_file():
        raise FileNotFoundError(f"Source dataset not found: {source}")
    if output.resolve() == source.resolve():
        raise RuntimeError("Refusing to overwrite the original dataset.")

    original_bytes = source.read_bytes()
    original_hash = hashlib.sha256(original_bytes).hexdigest()
    newline = _newline_for(original_bytes)

    if not BACKUP_PATH.exists():
        shutil.copyfile(source, BACKUP_PATH)
    backup_hash = sha256_file(BACKUP_PATH)
    if backup_hash != original_hash:
        raise RuntimeError(
            "The existing backup does not match the original dataset; refusing "
            "to proceed."
        )

    rows = generate_rows(seed=seed)
    generated_bytes = _csv_rows_bytes(rows, newline)
    separator = b"" if original_bytes.endswith((b"\n", b"\r")) else newline
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(original_bytes + separator + generated_bytes)

    if sha256_file(source) != original_hash:
        raise RuntimeError("The original dataset changed during generation.")
    if not output.read_bytes().startswith(original_bytes):
        raise RuntimeError("Expanded dataset does not preserve original bytes.")

    counts = Counter((row["age_band"] for row in rows))
    breed_counts = Counter((row["breed"] for row in rows))
    breed_sex_counts = Counter((row["breed"], row["sex"]) for row in rows)
    weight_by_band: dict[str, dict[str, float]] = {}
    price_by_band: dict[str, dict[str, float]] = {}
    for band_name, _, _, _ in AGE_BANDS:
        band_rows = [row for row in rows if row["age_band"] == band_name]
        weights = [float(row["weight_kg"]) for row in band_rows]
        prices = [
            float(row["actual_sale_price"].replace("\u20b1", "").replace(",", ""))
            for row in band_rows
        ]
        weight_by_band[band_name] = {
            "min_kg": min(weights),
            "max_kg": max(weights),
        }
        price_by_band[band_name] = {
            "min_php": min(prices),
            "max_php": max(prices),
        }

    manifest: dict[str, Any] = {
        "generated_at_utc": datetime.now(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "seed": seed,
        "days_per_month": DAYS_PER_MONTH,
        "source_file": source.name,
        "source_sha256": original_hash,
        "backup_file": BACKUP_PATH.name,
        "backup_sha256": backup_hash,
        "output_file": output.name,
        "output_sha256": sha256_file(output),
        "original_rows": 2000,
        "generated_rows": len(rows),
        "expanded_rows": 2000 + len(rows),
        "age_band_counts": dict(counts),
        "breed_counts": dict(breed_counts),
        "breed_sex_counts": {
            f"{breed}/{sex}": count
            for (breed, sex), count in sorted(breed_sex_counts.items())
        },
        "weight_range_by_band_kg": weight_by_band,
        "price_range_by_band_php": price_by_band,
        "assumptions": [
            "Synthetic records only; prices are not verified market quotes.",
            "Weight follows a simple breed-specific hatch-to-30-day curve with "
            "a +/-5% deterministic jitter and a 3% sex adjustment.",
            "Price is a synthetic base handling amount plus weight times a "
            "breed-specific PHP/kg rate, with a +/-8% deterministic jitter.",
            "Age is days / 30.4375 and is stored with six decimals.",
            "Four supported chicken breeds and both sexes appear in every "
            "age band.",
        ],
        "warning": (
            "Prototype data only. Do not use these synthetic prices as evidence "
            "of real-market value."
        ),
    }

    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    MANIFEST_PATH.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return manifest


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate young-chicken rows and build the expanded v2 CSV."
    )
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        manifest = build_output(args.source, args.output, seed=args.seed)
    except (FileNotFoundError, RuntimeError, ValueError) as exc:
        print(f"Generation failed: {exc}")
        return 1

    print(f"Expanded dataset: {args.output}")
    print(f"Manifest: {MANIFEST_PATH}")
    print(f"Original rows preserved: {manifest['original_rows']}")
    print(f"Young chicken rows added: {manifest['generated_rows']}")
    print(f"Expanded rows: {manifest['expanded_rows']}")
    print("Age bands:", manifest["age_band_counts"])
    print("Breeds:", manifest["breed_counts"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
