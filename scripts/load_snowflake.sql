-- load_snowflake.sql
-- Loads DuckDB mart CSVs into Snowflake for Sigma connection.
-- Run after: python scripts/export_marts.py
--
-- Prerequisites:
--   1. Snowflake free trial: https://signup.snowflake.com
--   2. Sigma free trial via Snowflake PartnerConnect (one click)
--   3. snowsql installed: https://docs.snowflake.com/en/user-guide/snowsql-install-config
--
-- Usage:
--   snowsql -a <your-account> -u <your-user> -f scripts/load_snowflake.sql

-- ── Setup ──────────────────────────────────────────────────────────────────

CREATE DATABASE IF NOT EXISTS DOORDASH_MERCHANT_INTELLIGENCE;
USE DATABASE DOORDASH_MERCHANT_INTELLIGENCE;

CREATE SCHEMA IF NOT EXISTS MARTS;
USE SCHEMA MARTS;

CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
  WAREHOUSE_SIZE = 'X-SMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;

USE WAREHOUSE COMPUTE_WH;

-- ── File format ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FILE FORMAT CSV_FORMAT
  TYPE = 'CSV'
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  SKIP_HEADER = 1
  NULL_IF = ('', 'None', 'NULL');

-- ── Stage (for local file upload) ───────────────────────────────────────────

CREATE OR REPLACE STAGE MART_STAGE FILE_FORMAT = CSV_FORMAT;

-- PUT the CSV files (run from your terminal after connecting via snowsql):
-- PUT file://./exports/mart_merchant_performance.csv @MART_STAGE;
-- PUT file://./exports/mart_cuisine_market_share.csv @MART_STAGE;
-- PUT file://./exports/mart_reviewer_cohort_retention.csv @MART_STAGE;
-- PUT file://./exports/mart_delivery_operations.csv @MART_STAGE;

-- ── Tables ──────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE MART_MERCHANT_PERFORMANCE (
    BUSINESS_ID             VARCHAR,
    BUSINESS_NAME           VARCHAR,
    CITY                    VARCHAR,
    STATE                   VARCHAR,
    PRIMARY_CUISINE         VARCHAR,
    LATITUDE                DOUBLE,
    LONGITUDE               DOUBLE,
    IS_OPEN                 BOOLEAN,
    YELP_STARS              DOUBLE,
    AVG_REVIEW_STARS        DOUBLE,
    TOTAL_REVIEWS           INTEGER,
    REVIEWS_PER_MONTH       DOUBLE,
    TOTAL_CHECKINS          INTEGER,
    ACTIVE_CHECKIN_DAYS     INTEGER,
    POSITIVE_REVIEW_RATIO   DOUBLE,
    ACTIVE_YEARS            INTEGER,
    COMPOSITE_SCORE         DOUBLE,
    PERFORMANCE_TIER        INTEGER,
    STATE_PERFORMANCE_TIER  INTEGER,
    TIER_LABEL              VARCHAR,
    IS_ELITE_MERCHANT       BOOLEAN,
    IS_CLOSED               BOOLEAN
);

CREATE OR REPLACE TABLE MART_CUISINE_MARKET_SHARE (
    STATE                   VARCHAR,
    PRIMARY_CUISINE         VARCHAR,
    MERCHANT_COUNT          INTEGER,
    TOTAL_MERCHANTS_IN_STATE INTEGER,
    MARKET_SHARE_PCT        DOUBLE,
    AVG_STARS               DOUBLE,
    AVG_REVIEWS_PER_MONTH   DOUBLE,
    AVG_CHECKINS            DOUBLE,
    AVG_COMPOSITE_SCORE     DOUBLE,
    TOTAL_REVIEWS_IN_SEGMENT INTEGER,
    OPEN_MERCHANT_COUNT     INTEGER,
    ELITE_MERCHANT_SHARE    DOUBLE,
    CUISINE_RANK_IN_STATE   INTEGER
);

CREATE OR REPLACE TABLE MART_REVIEWER_COHORT_RETENTION (
    COHORT_MONTH            DATE,
    COHORT_LABEL            VARCHAR,
    MONTHS_SINCE_COHORT     INTEGER,
    COHORT_SIZE             INTEGER,
    RETAINED_USERS          INTEGER,
    RETENTION_RATE_PCT      DOUBLE
);

CREATE OR REPLACE TABLE MART_DELIVERY_OPERATIONS (
    BUSINESS_ID             VARCHAR,
    BUSINESS_NAME           VARCHAR,
    CITY                    VARCHAR,
    STATE                   VARCHAR,
    PRIMARY_CUISINE         VARCHAR,
    PERFORMANCE_TIER        INTEGER,
    TIER_LABEL              VARCHAR,
    ORDER_MONTH             DATE,
    ORDER_DAY_OF_WEEK       VARCHAR,
    TOTAL_ORDERS            INTEGER,
    DELIVERED_ORDERS        INTEGER,
    CANCELLED_ORDERS        INTEGER,
    FULFILLMENT_RATE        DOUBLE,
    ON_TIME_RATE            DOUBLE,
    AVG_DELIVERY_MIN        DOUBLE,
    P90_DELIVERY_MIN        DOUBLE,
    TOTAL_GMV_USD           DOUBLE,
    AVG_ORDER_VALUE_USD     DOUBLE,
    TOTAL_DELIVERY_FEES_USD DOUBLE,
    _IS_SYNTHETIC_DATA      BOOLEAN
);

-- ── Load ────────────────────────────────────────────────────────────────────

COPY INTO MART_MERCHANT_PERFORMANCE
    FROM @MART_STAGE/mart_merchant_performance.csv
    FILE_FORMAT = CSV_FORMAT;

COPY INTO MART_CUISINE_MARKET_SHARE
    FROM @MART_STAGE/mart_cuisine_market_share.csv
    FILE_FORMAT = CSV_FORMAT;

COPY INTO MART_REVIEWER_COHORT_RETENTION
    FROM @MART_STAGE/mart_reviewer_cohort_retention.csv
    FILE_FORMAT = CSV_FORMAT;

COPY INTO MART_DELIVERY_OPERATIONS
    FROM @MART_STAGE/mart_delivery_operations.csv
    FILE_FORMAT = CSV_FORMAT;

-- ── Verify ──────────────────────────────────────────────────────────────────

SELECT 'mart_merchant_performance',     count(*) FROM MART_MERCHANT_PERFORMANCE    UNION ALL
SELECT 'mart_cuisine_market_share',     count(*) FROM MART_CUISINE_MARKET_SHARE    UNION ALL
SELECT 'mart_reviewer_cohort_retention',count(*) FROM MART_REVIEWER_COHORT_RETENTION UNION ALL
SELECT 'mart_delivery_operations',      count(*) FROM MART_DELIVERY_OPERATIONS;

-- ── Next: connect Sigma ──────────────────────────────────────────────────────
-- In Snowflake UI: Admin → Partner Connect → Sigma Computing → Connect
-- This creates your Sigma trial pre-wired to this Snowflake account.
-- Then in Sigma: New Workbook → select DOORDASH_MERCHANT_INTELLIGENCE.MARTS
