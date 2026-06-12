-- 19-cleanse-email-interaction.sql  [cleanse]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  staging.stg_file_email_interaction
-- writes: ods.ods_email_interaction

-- Cleanse staging.stg_file_email_interaction -> ods.ods_email_interaction: epoch casting + PK dedup.
-- Staging carries ~0.5% duplicate PKs by design; latest row wins.
-- Epoch encoding: millis (SFTP file feed) → TIMESTAMP_MILLIS per EPOCH-POLICY.md.

DECLARE run_date DATE DEFAULT CURRENT_DATE();

DELETE FROM ods.ods_email_interaction WHERE event_date = run_date;

INSERT INTO ods.ods_email_interaction
SELECT
  s.email_ref                                                            AS email_ref,
  s.client_code                                                          AS client_code,
  s.mailbox                                                              AS mailbox,
  s.agent_email                                                          AS agent_email,
  TIMESTAMP_MILLIS(s.received_ms)                                        AS received_ts,
  TIMESTAMP_MILLIS(s.first_reply_ms)                                     AS first_reply_ts,
  TIMESTAMP_MILLIS(s.resolved_ms)                                        AS resolved_ts,
  CAST((s.first_reply_ms - s.received_ms) / 60000 AS INT64)             AS reply_sla_minutes,
  s.subject_category                                                     AS subject_category,
  DATE(TIMESTAMP_MILLIS(s.received_ms))                                  AS event_date
FROM (
  SELECT s.*,
         ROW_NUMBER() OVER (PARTITION BY s.email_ref ORDER BY s.received_ms DESC) AS rn
  FROM staging.stg_file_email_interaction s
  WHERE s.load_date = run_date
) s
WHERE s.rn = 1;
