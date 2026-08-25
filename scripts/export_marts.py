"""
export_marts.py
───────────────
Exports all gold mart tables from DuckDB to CSV for upload to
Tableau Public (local dev) or Snowflake/Sigma (production).

Usage:
    python scripts/export_marts.py
    python scripts/export_marts.py --db ./dbt_project/dev.duckdb --out ./exports

Outputs:
    exports/mart_merchant_performance.csv
    exports/mart_cuisine_market_share.csv
    exports/mart_reviewer_cohort_retention.csv
    exports/mart_delivery_operations.csv
    exports/export_summary.txt
"""

import argparse
import os
import duckdb
import pandas as pd
from datetime import datetime


MARTS = {
    "mart_merchant_performance":    "doordash_marts",
    "mart_cuisine_market_share":    "doordash_marts",
    "mart_reviewer_cohort_retention": "doordash_marts",
    "mart_delivery_operations":     "doordash_marts",
}


def export_mart(conn, schema: str, table: str, out_dir: str) -> dict:
    df = conn.execute(f'SELECT * FROM "{schema}"."{table}"').df()
    path = os.path.join(out_dir, f"{table}.csv")
    df.to_csv(path, index=False)
    return {
        "table":   table,
        "rows":    len(df),
        "cols":    len(df.columns),
        "size_kb": round(os.path.getsize(path) / 1024, 1),
        "path":    path,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db",  default="./dbt_project/dev.duckdb")
    parser.add_argument("--out", default="./exports")
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)
    conn = duckdb.connect(args.db, read_only=True)

    print(f"\n{'='*55}")
    print("Mart Export — DuckDB → CSV")
    print(f"  Source : {args.db}")
    print(f"  Output : {args.out}")
    print(f"{'='*55}\n")

    results = []
    for table, schema in MARTS.items():
        try:
            r = export_mart(conn, schema, table, args.out)
            results.append(r)
            print(f"  ✓ {table}")
            print(f"      {r['rows']:,} rows × {r['cols']} cols  ({r['size_kb']} KB)")
        except Exception as e:
            print(f"  ✗ {table}: {e}")

    # Summary file for README
    summary_path = os.path.join(args.out, "export_summary.txt")
    with open(summary_path, "w") as f:
        f.write(f"Export generated: {datetime.now().isoformat()}\n")
        f.write(f"Source: {args.db}\n\n")
        for r in results:
            f.write(f"{r['table']}: {r['rows']:,} rows, {r['size_kb']} KB\n")

    print(f"\n✓ Export complete → {args.out}/")
    print(f"  Summary: {summary_path}")
    print(f"\nNext steps:")
    print(f"  Tableau Public: File → Open → each CSV, then publish")
    print(f"  Snowflake: snowsql -f scripts/load_snowflake.sql")
    conn.close()


if __name__ == "__main__":
    main()
