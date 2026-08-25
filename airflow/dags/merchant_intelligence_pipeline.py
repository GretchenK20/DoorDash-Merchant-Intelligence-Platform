"""
merchant_intelligence_pipeline.py
──────────────────────────────────
Airflow DAG: orchestrates the full DoorDash Merchant Intelligence pipeline.

Pipeline:
  bronze_ingest          PySpark: Yelp JSON → Delta Lake (MinIO)
    ↓
  synthetic_generate     Generate synthetic order events
    ↓
  silver_transform       dbt run: staging models
    ↓
  silver_validate        Great Expectations: validate silver layer
    ↓ (fails here if GE checks fail — gold never runs on bad data)
  gold_transform         dbt run: intermediate + mart models
    ↓
  gold_test              dbt test: all mart-level tests
    ↓
  notify_success         Log completion metrics

Schedule: daily at 3am UTC (off-peak)
"""

from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator, BranchPythonOperator
from airflow.operators.empty import EmptyOperator
from airflow.utils.trigger_rule import TriggerRule


# ── DAG Config ────────────────────────────────────────────────────────────────

DEFAULT_ARGS = {
    "owner":            "gretchen.kolthoff",
    "depends_on_past":  False,
    "email_on_failure": True,
    "email":            ["gretchenkolt@icloud.com"],
    "retries":          2,
    "retry_delay":      timedelta(minutes=5),
}

PROJECT_ROOT = "/opt/airflow"
DBT_PROJECT  = f"{PROJECT_ROOT}/dbt_project"
GE_PATH      = f"{PROJECT_ROOT}/great_expectations"

# ── DAG ───────────────────────────────────────────────────────────────────────

with DAG(
    dag_id="merchant_intelligence_pipeline",
    description="DoorDash Merchant Intelligence — full lakehouse pipeline",
    schedule_interval="0 3 * * *",   # 3am UTC daily
    start_date=datetime(2024, 1, 1),
    catchup=False,
    default_args=DEFAULT_ARGS,
    tags=["merchant", "lakehouse", "delta-lake", "dbt"],
    doc_md="""
    ## DoorDash Merchant Intelligence Pipeline

    Mirrors DoorDash's production lakehouse architecture:
    - **Bronze**: PySpark ingestion → Delta Lake on MinIO (S3-compatible)
    - **Silver**: dbt staging models via Trino, validated with Great Expectations
    - **Gold**: dbt intermediate + mart models (canonical datasets)

    ### Failure behavior
    - `silver_validate` failing blocks all gold transforms (by design)
    - All GE critical failures trigger immediate alert
    - Gold tests failing sends notification but does not retry (data issue)
    """,
) as dag:

    # ── Start ──────────────────────────────────────────────────────────────
    start = EmptyOperator(task_id="start")

    # ── Bronze: PySpark ingest ─────────────────────────────────────────────
    bronze_ingest = BashOperator(
        task_id="bronze_ingest",
        bash_command=(
            "spark-submit "
            "--packages io.delta:delta-spark_2.12:3.2.0,"
            "org.apache.hadoop:hadoop-aws:3.3.4 "
            f"{PROJECT_ROOT}/ingestion/bronze_ingest.py "
            "--yelp_data_dir /data/yelp_dataset "
            "--output_path s3a://lakehouse/bronze"
        ),
        doc_md="PySpark: Yelp JSON → Delta Lake on MinIO",
    )

    # ── Synthetic: generate order events ──────────────────────────────────
    synthetic_generate = BashOperator(
        task_id="synthetic_generate",
        bash_command=(
            f"python {PROJECT_ROOT}/synthetic/generate_orders.py "
            "--yelp_data_dir /data/yelp_dataset "
            "--output /data/synthetic/orders.parquet "
            "--n_orders 500000"
        ),
        doc_md="Generate 500K synthetic order events (clearly labeled)",
    )

    # ── Silver: dbt staging models ─────────────────────────────────────────
    silver_transform = BashOperator(
        task_id="silver_transform",
        bash_command=(
            f"cd {DBT_PROJECT} && "
            "dbt run --select staging --target trino --profiles-dir ."
        ),
        doc_md="dbt: run all staging (silver) models via Trino",
    )

    # ── Silver: Great Expectations validation ─────────────────────────────
    def run_ge_validation(**context):
        """
        Run GE suite. Returns 'gold_transform' if all pass,
        'validation_failed' if any critical checks fail.
        """
        import subprocess, sys
        result = subprocess.run(
            [sys.executable, f"{GE_PATH}/validate_silver.py"],
            capture_output=True, text=True
        )
        print(result.stdout)
        if result.returncode != 0:
            print(result.stderr)
            return "validation_failed"
        return "gold_transform"

    silver_validate = BranchPythonOperator(
        task_id="silver_validate",
        python_callable=run_ge_validation,
        doc_md="Great Expectations: validate silver layer before gold runs",
    )

    # ── Validation failed branch ───────────────────────────────────────────
    validation_failed = BashOperator(
        task_id="validation_failed",
        bash_command=(
            "echo 'GE VALIDATION FAILED — gold layer blocked' && "
            "exit 1"
        ),
        trigger_rule=TriggerRule.ONE_SUCCESS,
    )

    # ── Gold: dbt intermediate + mart models ──────────────────────────────
    gold_transform = BashOperator(
        task_id="gold_transform",
        bash_command=(
            f"cd {DBT_PROJECT} && "
            "dbt run --select intermediate marts --target trino --profiles-dir ."
        ),
        doc_md="dbt: run intermediate + mart (gold) models via Trino",
    )

    # ── Gold: dbt tests ───────────────────────────────────────────────────
    gold_test = BashOperator(
        task_id="gold_test",
        bash_command=(
            f"cd {DBT_PROJECT} && "
            "dbt test --select marts --target trino --profiles-dir ."
        ),
        doc_md="dbt: run all mart-level schema + custom tests",
    )

    # ── dbt docs: generate + upload ───────────────────────────────────────
    dbt_docs = BashOperator(
        task_id="dbt_docs_generate",
        bash_command=(
            f"cd {DBT_PROJECT} && "
            "dbt docs generate --target trino --profiles-dir ."
        ),
        doc_md="Generate dbt docs (data catalog / lineage)",
    )

    # ── Success notification ───────────────────────────────────────────────
    notify_success = BashOperator(
        task_id="notify_success",
        bash_command=(
            "echo 'Pipeline complete: "
            "bronze → silver (validated) → gold → docs' "
            "&& date"
        ),
        trigger_rule=TriggerRule.ALL_SUCCESS,
    )

    end = EmptyOperator(
        task_id="end",
        trigger_rule=TriggerRule.NONE_FAILED_MIN_ONE_SUCCESS,
    )

    # ── Task dependencies ─────────────────────────────────────────────────
    start >> [bronze_ingest, synthetic_generate]
    bronze_ingest      >> silver_transform
    synthetic_generate >> silver_transform
    silver_transform   >> silver_validate
    silver_validate    >> [gold_transform, validation_failed]
    gold_transform     >> gold_test >> dbt_docs >> notify_success
    [notify_success, validation_failed] >> end
