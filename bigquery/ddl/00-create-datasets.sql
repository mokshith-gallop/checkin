-- bigquery/ddl/00-create-datasets.sql
-- Creates the 3 BigQuery datasets (schemas) that mirror the Hive databases.
-- Run this BEFORE any table or view DDL.
--
-- Usage:
--   bq query --nouse_legacy_sql < 00-create-datasets.sql

CREATE SCHEMA IF NOT EXISTS staging
  OPTIONS (description = 'Sqoop + SFTP landing mirrors — epoch dates live here');

CREATE SCHEMA IF NOT EXISTS ods
  OPTIONS (description = 'Cleansed / conformed / merged — all TIMESTAMPs');

CREATE SCHEMA IF NOT EXISTS dm
  OPTIONS (description = 'Dimensional marts — dimensions, facts, aggregates, and analyst views');
