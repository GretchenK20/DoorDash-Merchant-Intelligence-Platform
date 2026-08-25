"""
bronze_ingest.py
────────────────
PySpark job: ingest Yelp Open Dataset JSON files into Delta Lake
on MinIO (S3-compatible). Writes bronze (raw) layer.

DoorDash parallel: their Data Ingestion team uses PySpark + Delta Lake
on S3 with Flink for streaming. We use PySpark batch here.

Usage:
    spark-submit \
        --packages io.delta:delta-spark_2.12:3.2.0,\
org.apache.hadoop:hadoop-aws:3.3.4 \
        ingestion/bronze_ingest.py \
        --yelp_data_dir /path/to/yelp_dataset \
        --output_path s3a://lakehouse/bronze

Local dev (DuckDB mode — no Spark cluster needed):
    python ingestion/bronze_ingest.py --local
"""

import argparse
import os
from pyspark.sql import SparkSession
from pyspark.sql import functions as F


MINIO_ENDPOINT   = os.getenv("MINIO_ENDPOINT",   "http://localhost:9000")
MINIO_ACCESS_KEY = os.getenv("MINIO_ACCESS_KEY",  "minioadmin")
MINIO_SECRET_KEY = os.getenv("MINIO_SECRET_KEY",  "minioadmin")


def build_spark(local: bool = False) -> SparkSession:
    """
    Build a SparkSession configured for Delta Lake + MinIO.
    In local mode we skip S3 config and write to local filesystem instead.
    """
    builder = (
        SparkSession.builder
        .appName("doordash-merchant-intelligence-bronze")
        .config("spark.sql.extensions",
                "io.delta.sql.DeltaSparkSessionExtension")
        .config("spark.sql.catalog.spark_catalog",
                "org.apache.spark.sql.delta.catalog.DeltaCatalog")
    )

    if not local:
        builder = (
            builder
            # Delta Lake JAR
            .config("spark.jars.packages",
                    "io.delta:delta-spark_2.12:3.2.0,"
                    "org.apache.hadoop:hadoop-aws:3.3.4")
            # MinIO / S3 config
            .config("spark.hadoop.fs.s3a.endpoint",       MINIO_ENDPOINT)
            .config("spark.hadoop.fs.s3a.access.key",     MINIO_ACCESS_KEY)
            .config("spark.hadoop.fs.s3a.secret.key",     MINIO_SECRET_KEY)
            .config("spark.hadoop.fs.s3a.path.style.access", "true")
            .config("spark.hadoop.fs.s3a.impl",
                    "org.apache.hadoop.fs.s3a.S3AFileSystem")
        )

    return builder.master("local[*]").getOrCreate()


def ingest_businesses(spark: SparkSession, src: str, dest: str) -> None:
    """
    Ingest yelp_academic_dataset_business.json → bronze/businesses

    Key fields we care about:
        business_id, name, address, city, state, postal_code,
        latitude, longitude, stars, review_count, is_open,
        categories, hours (struct)
    """
    print("▶ Ingesting businesses...")
    df = (
        spark.read.json(f"{src}/yelp_academic_dataset_business.json")
        # Add ingestion metadata — standard practice for bronze layer
        .withColumn("_ingested_at",  F.current_timestamp())
        .withColumn("_source_file",  F.lit("yelp_academic_dataset_business.json"))
        .withColumn("_batch_date",   F.current_date())
    )
    print(f"  Loaded {df.count():,} business records")

    (
        df.write
        .format("delta")
        .mode("overwrite")
        .option("overwriteSchema", "true")
        # Partition by state — aligns with our gold-layer query pattern
        .partitionBy("state")
        .save(f"{dest}/businesses")
    )
    print(f"  ✓ Written → {dest}/businesses")


def ingest_reviews(spark: SparkSession, src: str, dest: str) -> None:
    """
    Ingest yelp_academic_dataset_review.json → bronze/reviews

    Key fields:
        review_id, user_id, business_id, stars, useful, funny, cool,
        text, date
    """
    print("▶ Ingesting reviews...")
    df = (
        spark.read.json(f"{src}/yelp_academic_dataset_review.json")
        .withColumn("_ingested_at", F.current_timestamp())
        .withColumn("_source_file", F.lit("yelp_academic_dataset_review.json"))
        .withColumn("_batch_date",  F.current_date())
        # Parse date string → proper date type at ingest
        .withColumn("review_date",  F.to_date("date", "yyyy-MM-dd"))
    )
    print(f"  Loaded {df.count():,} review records")

    (
        df.write
        .format("delta")
        .mode("overwrite")
        .option("overwriteSchema", "true")
        # Partition by year for time-series query efficiency
        .partitionBy(F.year("review_date").alias("review_year"))
        .save(f"{dest}/reviews")
    )
    print(f"  ✓ Written → {dest}/reviews")


def ingest_checkins(spark: SparkSession, src: str, dest: str) -> None:
    """
    Ingest yelp_academic_dataset_checkin.json → bronze/checkins

    Schema: business_id, date (comma-separated timestamp strings)
    We explode the date field into individual check-in events.
    """
    print("▶ Ingesting checkins...")
    df = (
        spark.read.json(f"{src}/yelp_academic_dataset_checkin.json")
        # Explode comma-separated timestamps into individual rows
        .withColumn("checkin_timestamps",
                    F.split(F.col("date"), ", "))
        .withColumn("checkin_at",
                    F.explode("checkin_timestamps"))
        .withColumn("checkin_at",
                    F.to_timestamp("checkin_at", "yyyy-MM-dd HH:mm:ss"))
        .drop("date", "checkin_timestamps")
        .withColumn("_ingested_at", F.current_timestamp())
        .withColumn("_source_file", F.lit("yelp_academic_dataset_checkin.json"))
        .withColumn("_batch_date",  F.current_date())
    )
    print(f"  Loaded {df.count():,} checkin events (post-explode)")

    (
        df.write
        .format("delta")
        .mode("overwrite")
        .option("overwriteSchema", "true")
        .save(f"{dest}/checkins")
    )
    print(f"  ✓ Written → {dest}/checkins")


def main():
    parser = argparse.ArgumentParser(
        description="Bronze ingestion: Yelp JSON → Delta Lake"
    )
    parser.add_argument("--yelp_data_dir", default="./data/yelp_dataset",
                        help="Path to Yelp dataset directory")
    parser.add_argument("--output_path", default="s3a://lakehouse/bronze",
                        help="Delta Lake output root")
    parser.add_argument("--local", action="store_true",
                        help="Write to local filesystem instead of MinIO")
    args = parser.parse_args()

    if args.local:
        args.output_path = "./data/bronze"

    spark = build_spark(local=args.local)
    spark.sparkContext.setLogLevel("WARN")

    print(f"\n{'='*60}")
    print(f"Bronze Ingestion — Yelp Open Dataset → Delta Lake")
    print(f"  Source : {args.yelp_data_dir}")
    print(f"  Dest   : {args.output_path}")
    print(f"{'='*60}\n")

    ingest_businesses(spark, args.yelp_data_dir, args.output_path)
    ingest_reviews(spark,    args.yelp_data_dir, args.output_path)
    ingest_checkins(spark,   args.yelp_data_dir, args.output_path)

    print("\n✓ Bronze ingestion complete.")
    spark.stop()


if __name__ == "__main__":
    main()
