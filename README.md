# DoorDash Merchant Intelligence Platform

## Live Dashboard (Snowflake, Sigma, Python, PySpark, DBT, Great Expectations, Airflow, CI/CD)
[DoorDash Merchant Intelligence Platform (Sigma)](https://app.sigmacomputing.com/omc31389/workbook/DoorDash-Merchant-Intelligence-Platform-4nEFQjxFJTkt572hZojZuK)


A production-grade lakehouse analytics platform built to mirror DoorDash's
internal data architecture — demonstrating the exact stack used.

**Dataset:** [Yelp Open Dataset](https://www.yelp.com/dataset) (150K+ businesses, 7M+ reviews)
**License:** Yelp Open Dataset License (academic/personal use)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    BRONZE LAYER                             │
│  PySpark ──► Delta Lake on MinIO (S3-compatible)           │
│  • yelp businesses (partitioned by state)                   │
│  • yelp reviews    (partitioned by review_year)             │
│  • yelp checkins   (exploded from comma-separated ts)       │
│  • synthetic orders (500K events, _is_synthetic=True)       │
└────────────────────────┬────────────────────────────────────┘
                         │ registered in Hive Metastore
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    SILVER LAYER                             │
│  dbt staging models via Trino (distributed SQL engine)      │
│  • stg_yelp_businesses  (filtered, typed, cuisine-parsed)   │
│  • stg_yelp_reviews     (cleaned, sentiment-bucketed)       │
│  • stg_yelp_checkins    (aggregated to daily counts)        │
│  • stg_synthetic_orders (typed, labeled)                    │
│                                                             │
│  Great Expectations validation suite (runs here)            │
│  • Completeness, Validity, Uniqueness, Volume checks        │
│  • Blocks gold layer if any critical check fails            │
└────────────────────────┬────────────────────────────────────┘
                         │ GE checkpoint must pass
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                     GOLD LAYER (Canonical Marts)            │
│  dbt intermediate + mart models via Trino                   │
│                                                             │
│  int_merchant_activity          (businesses + reviews + checkins)
│                                                             │
│  mart_merchant_performance      Composite scoring, tiers    │
│  mart_cuisine_market_share      Market penetration by state │
│  mart_reviewer_cohort_retention Monthly cohort retention    │
│  mart_delivery_operations       Fulfillment, GMV (synthetic)│
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    BI LAYER                                 │
│  Sigma self-serve dashboard (DoorDash's primary BI tool)    │
│  • Merchant Performance tab                                 │
│  • Market Intelligence tab                                  │
│  • Operations tab (synthetic — labeled)                     │
└─────────────────────────────────────────────────────────────┘
                         │
              Orchestrated by Apache Airflow
              CI/CD via GitHub Actions
```

---

## Stack

| Component | Tool | DoorDash parallel |
|---|---|---|
| Object storage | MinIO (S3-compatible) | AWS S3 |
| Table format | Delta Lake | Delta Lake |
| Query engine | Trino | Trino |
| Table catalog | Hive Metastore | Hive Metastore |
| Batch processing | PySpark | Apache Spark |
| Transformation | dbt (dbt-trino adapter) | dbt |
| Data quality | Great Expectations | Great Expectations / Pydeequ |
| Orchestration | Apache Airflow | Apache Airflow |
| BI / dashboarding | Sigma | Sigma |
| CI/CD | GitHub Actions | — |

---

## Quick Start

### Prerequisites
- Docker + Docker Compose
- Python 3.11+
- [Yelp Open Dataset](https://www.yelp.com/dataset) (download and place in `data/yelp_dataset/`)

### 1. Start the stack
```bash
docker-compose up -d

# Wait for all services to be healthy (~2 min)
docker-compose ps
```

### 2. Install Python dependencies
```bash
pip install -r requirements.txt
```

### 3. Generate synthetic orders
```bash
python synthetic/generate_orders.py \
  --yelp_data_dir ./data/yelp_dataset \
  --output ./data/synthetic/orders.parquet
```

### 4. Run bronze ingestion (PySpark)
```bash
spark-submit \
  --packages io.delta:delta-spark_2.12:3.2.0,org.apache.hadoop:hadoop-aws:3.3.4 \
  ingestion/bronze_ingest.py \
  --yelp_data_dir ./data/yelp_dataset \
  --output_path s3a://lakehouse/bronze
```

### 5. Run dbt (silver → gold)
```bash
cd dbt_project
dbt deps
# Silver (staging)
dbt run --select staging --target trino
# Validate silver with Great Expectations
python ../great_expectations/validate_silver.py
# Gold (intermediate + marts)
dbt run --select intermediate marts --target trino
dbt test --select marts --target trino
```

### 6. Open dashboards
- **MinIO Console:** http://localhost:9001 (minioadmin / minioadmin)
- **Trino UI:** http://localhost:8080
- **Airflow:** http://localhost:8081 (admin / admin)

---

## Local Development (no Docker)

Use the `dev` dbt target (DuckDB) for fast iteration:
```bash
cd dbt_project
dbt run --target dev   # runs against local DuckDB
dbt test --target dev
```

DuckDB is SQL-compatible with Trino for all models in this project.
Switch to `--target trino` for production runs.

---

## SQL Performance Tuning

See [`docs/trino_query_tuning.md`](docs/trino_query_tuning.md) for:
- EXPLAIN ANALYZE output before/after partitioning `mart_merchant_performance`
- 92% row scan reduction from `state` partitioning
- 85% further reduction from `primary_cuisine` clustering
- 235x query improvement from CTE refactor in cohort retention mart

---

## Note on Synthetic Data

The `mart_delivery_operations` mart and `stg_synthetic_orders` staging model
are built on **synthetic order data** generated by `synthetic/generate_orders.py`.
Every synthetic row carries `_is_synthetic = True`. The Sigma dashboard labels
the Operations tab accordingly. This was added to provide a delivery operations
dimension that the static Yelp snapshot data cannot supply.

---

## Project Structure

```
doordash_merchant_intelligence/
├── ingestion/
│   └── bronze_ingest.py          PySpark: Yelp → Delta Lake
├── synthetic/
│   └── generate_orders.py        Synthetic order event generator
├── dbt_project/
│   ├── models/
│   │   ├── staging/              Silver layer (stg_*)
│   │   ├── intermediate/         int_merchant_activity
│   │   └── marts/                4 canonical mart tables
│   ├── macros/
│   │   └── months_diff.sql       Cross-dialect date macro
│   └── profiles.yml              Trino (prod) + DuckDB (dev)
├── great_expectations/
│   └── validate_silver.py        GE validation suite
├── airflow/
│   └── dags/
│       └── merchant_intelligence_pipeline.py
├── docs/
│   └── trino_query_tuning.md     EXPLAIN analysis + tuning decisions
├── scripts/
│   └── trino/                    Trino config + catalog
├── .github/workflows/
│   └── ci.yml                    GitHub Actions CI
├── docker-compose.yml
├── requirements.txt
└── README.md
```
