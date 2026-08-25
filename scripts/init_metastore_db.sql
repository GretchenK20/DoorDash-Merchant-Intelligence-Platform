-- Creates the Hive Metastore database alongside Airflow's DB
CREATE DATABASE metastore;
GRANT ALL PRIVILEGES ON DATABASE metastore TO airflow;
