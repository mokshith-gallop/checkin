-- bigquery/ddl/dm/vw_billing_reconciliation.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive): 09-dm-views.hql — view #6
-- Trap: compares the RAW staging epoch — including the lying issued_ts_sec
--       millis column — against the cleansed ACID TIMESTAMP value.
--
-- Conversion notes:
--   - Hive from_unixtime(x) → BigQuery TIMESTAMP_SECONDS(x).
--     Converts epoch seconds to TIMESTAMP.
--   - Hive unix_timestamp(ts) → BigQuery UNIX_SECONDS(ts).
--     Converts TIMESTAMP to epoch seconds.
--   - The /1000 division is preserved because issued_ts_sec is a LYING column:
--     the name says seconds but values are actually milliseconds.
--   - Hive CAST(x AS BIGINT) → BigQuery CAST(x AS INT64).
--   - Hive ABS() → BigQuery ABS() (identical).

CREATE VIEW IF NOT EXISTS dm.vw_billing_reconciliation AS
SELECT s.invoice_no,
       s.total_amount                                    AS staged_amount,
       a.total_amount                                    AS ods_amount,
       TIMESTAMP_SECONDS(CAST(s.issued_ts_sec / 1000 AS INT64)) AS staged_issued_ts,  -- /1000: column lies
       a.issued_ts                                       AS ods_issued_ts,
       (UNIX_SECONDS(a.issued_ts) - CAST(s.issued_ts_sec / 1000 AS INT64)) AS drift_seconds,
       CASE WHEN ABS(s.total_amount - a.total_amount) > 0.01 THEN 'AMOUNT_MISMATCH'
            WHEN UNIX_SECONDS(a.issued_ts) <> CAST(s.issued_ts_sec / 1000 AS INT64) THEN 'TS_MISMATCH'
            ELSE 'OK' END                                AS recon_status
FROM   staging.stg_fin_invoice s
JOIN   ods.ods_invoice_acid a ON a.invoice_id = s.invoice_id;
