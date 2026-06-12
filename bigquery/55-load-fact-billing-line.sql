-- 55-load-fact-billing-line.sql  [fact]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  ods.ods_invoice_acid, staging.stg_fin_invoice_line, ods.ods_rate_card, dm.dim_program
-- writes: dm.fact_billing_line

-- LAYER-SKIP TRAP: invoice LINES come straight from staging (epoch millis in
-- created_ms never cast — nobody noticed because the column is unused
-- downstream). Headers come from the cleansed ACID table.
-- Partition is period_month (STRING), not date_key (INT64).
-- substr('${var:run_date}', 1, 7) → period_month_val scripting variable.

DECLARE run_date DATE DEFAULT CURRENT_DATE();
DECLARE period_month_val STRING DEFAULT FORMAT_DATE('%Y-%m', run_date);

DELETE FROM dm.fact_billing_line WHERE period_month = period_month_val;

INSERT INTO dm.fact_billing_line
SELECT
  l.invoice_line_id,
  i.invoice_id,
  COALESCE(c.client_sk, i.client_id) AS client_sk,
  COALESCE(p.program_sk, -1)         AS program_sk,
  COALESCE(r.service_code, 'UNKNOWN') AS service_code,
  l.qty,
  COALESCE(r.rate, l.unit_rate)      AS unit_rate,
  l.line_amount,
  l.adjustment_flag,
  i.status                           AS invoice_status,
  i.period_month
FROM staging.stg_fin_invoice_line l
JOIN ods.ods_invoice_acid i ON i.invoice_id = l.invoice_id
LEFT JOIN dm.dim_program p ON p.program_id = i.program_id
LEFT JOIN (SELECT c.client_id, c.client_id AS client_sk FROM ods.ods_client_acid c) c
       ON c.client_id = i.client_id
LEFT JOIN ods.ods_rate_card r
       ON r.program_id = i.program_id
      AND r.snapshot_date = run_date
WHERE i.period_month = period_month_val;
