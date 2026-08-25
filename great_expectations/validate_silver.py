"""
validate_silver.py
──────────────────
Great Expectations v1.x validation suite for the silver (staging) layer.

Local dev: validates DuckDB silver views built by dbt.
Production: swap DB_PATH for Trino JDBC connection in run_suite().

Expectation dimensions covered per table:
  Completeness — not_null checks on required columns
  Validity     — value ranges, accepted sets, coordinate bounds
  Uniqueness   — primary key integrity
  Volume       — row count thresholds (catch truncated loads)
"""

import sys
import os
import warnings
warnings.filterwarnings("ignore")

import duckdb
import great_expectations as gx
from great_expectations.expectations import (
    ExpectColumnValuesToNotBeNull,
    ExpectColumnValuesToBeUnique,
    ExpectColumnValuesToBeBetween,
    ExpectColumnValuesToBeInSet,
    ExpectTableRowCountToBeBetween,
)

DB_PATH = os.getenv(
    "DUCKDB_PATH",
    os.path.join(os.path.dirname(__file__), "../dbt_project/dev.duckdb")
)


def run_suite(table_schema: str, table_name: str, expectations: list, label: str) -> bool:
    """
    Run GE expectations against a DuckDB table using a Pandas batch.
    Returns True if all expectations pass.
    """
    print(f"\n── Validating {label} {'─' * max(0, 44 - len(label))}")

    conn = duckdb.connect(DB_PATH, read_only=True)
    df   = conn.execute(f'SELECT * FROM "{table_schema}"."{table_name}"').df()
    conn.close()

    print(f"  Rows: {len(df):,}  |  Cols: {list(df.columns)[:6]}...")

    # GE v1.x: use in-memory pandas batch via get_context
    ctx   = gx.get_context(mode="ephemeral")
    suite = ctx.suites.add(gx.ExpectationSuite(name=label))
    for exp in expectations:
        suite.add_expectation(exp)

    ds       = ctx.data_sources.add_pandas(name=f"pandas_{label}")
    asset    = ds.add_dataframe_asset(name=label)
    batch_def = asset.add_batch_definition_whole_dataframe("batch")
    batch    = batch_def.get_batch(batch_parameters={"dataframe": df})

    vd = ctx.validation_definitions.add(
        gx.ValidationDefinition(name=f"vd_{label}", data=batch_def, suite=suite)
    )
    results = vd.run(batch_parameters={"dataframe": df})

    passed = []
    for r in results.results:
        ok     = r.success
        passed.append(ok)
        status = "✓" if ok else "✗"
        exp_type = r.expectation_config.type
        kwargs   = {k: v for k, v in r.expectation_config.kwargs.items()
                    if k not in ("batch_id",)}
        print(f"  {status} {exp_type}  {kwargs}")
        if not ok:
            print(f"      → {r.result}")

    n, p = len(passed), sum(passed)
    print(f"\n  Result: {p}/{n} expectations passed")
    return all(passed)


# ── Expectation Suites ───────────────────────────────────────────────────────

def suite_businesses():
    return [
        ExpectColumnValuesToNotBeNull(column="business_id"),
        ExpectColumnValuesToNotBeNull(column="business_name"),
        ExpectColumnValuesToNotBeNull(column="state"),
        ExpectColumnValuesToNotBeNull(column="stars"),
        ExpectColumnValuesToNotBeNull(column="primary_cuisine"),
        ExpectColumnValuesToBeUnique(column="business_id"),
        ExpectColumnValuesToBeBetween(column="stars",        min_value=1.0, max_value=5.0),
        ExpectColumnValuesToBeBetween(column="review_count", min_value=1),
        ExpectColumnValuesToBeBetween(column="latitude",     min_value=18.0, max_value=72.0),
        ExpectColumnValuesToBeBetween(column="longitude",    min_value=-180.0, max_value=-65.0),
        ExpectTableRowCountToBeBetween(min_value=100, max_value=500_000),
    ]


def suite_reviews():
    return [
        ExpectColumnValuesToNotBeNull(column="review_id"),
        ExpectColumnValuesToNotBeNull(column="business_id"),
        ExpectColumnValuesToNotBeNull(column="review_date"),
        ExpectColumnValuesToBeUnique(column="review_id"),
        ExpectColumnValuesToBeBetween(column="review_stars", min_value=1.0, max_value=5.0),
        ExpectColumnValuesToBeBetween(column="review_year",  min_value=2015, max_value=2026),
        ExpectColumnValuesToBeInSet(
            column="sentiment_bucket",
            value_set=["positive", "neutral", "negative"],
        ),
        ExpectTableRowCountToBeBetween(min_value=100, max_value=10_000_000),
    ]


def suite_orders():
    return [
        ExpectColumnValuesToNotBeNull(column="order_id"),
        ExpectColumnValuesToNotBeNull(column="business_id"),
        ExpectColumnValuesToBeUnique(column="order_id"),
        ExpectColumnValuesToBeInSet(
            column="order_status",
            value_set=["delivered", "cancelled"],
        ),
        ExpectColumnValuesToBeBetween(
            column="order_total_usd",
            min_value=0.01,
            max_value=500.0,
        ),
        ExpectTableRowCountToBeBetween(min_value=1_000, max_value=600_000),
    ]


# ── Main ─────────────────────────────────────────────────────────────────────

def main() -> int:
    print("=" * 60)
    print("Great Expectations v1.x — Silver Layer Validation")
    print(f"  Database : {DB_PATH}")
    print("=" * 60)

    suites = [
        ("doordash_staging", "stg_yelp_businesses_dev",  suite_businesses(), "stg_yelp_businesses"),
        ("doordash_staging", "stg_yelp_reviews_dev",     suite_reviews(),    "stg_yelp_reviews"),
        ("doordash_staging", "stg_synthetic_orders_dev", suite_orders(),     "stg_synthetic_orders"),
    ]

    all_passed = True
    for schema, table, expectations, label in suites:
        try:
            ok = run_suite(schema, table, expectations, label)
        except Exception as e:
            print(f"\n  ✗ ERROR in {label}: {e}")
            ok = False
        all_passed = all_passed and ok

    print("\n" + "=" * 60)
    if all_passed:
        print("✓ ALL SUITES PASSED — safe to proceed to gold layer")
        return 0
    else:
        print("✗ VALIDATION FAILURES — review before proceeding to gold layer")
        return 1


if __name__ == "__main__":
    sys.exit(main())
