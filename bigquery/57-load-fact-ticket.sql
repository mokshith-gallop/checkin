-- 57-load-fact-ticket.sql  [fact]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  ods.ods_ticket_acid, staging.stg_tkt_ticket_event, staging.stg_tkt_category, dm.dim_agent
-- writes: dm.fact_ticket

-- Ticket fact: ACID master + raw events for touch counts (epoch millis,
-- layer-skip) + category SLA hours for breach flag.
-- unix_timestamp(ts) → UNIX_SECONDS(CAST(ts AS TIMESTAMP)).
-- to_date(ts) → DATE(ts).

DECLARE run_date DATE DEFAULT CURRENT_DATE();
DECLARE date_key_val INT64 DEFAULT CAST(FORMAT_DATE('%Y%m%d', run_date) AS INT64);

DELETE FROM dm.fact_ticket WHERE date_key = date_key_val;

INSERT INTO dm.fact_ticket
SELECT
  t.ticket_id,
  COALESCE(t.program_id, -1)          AS program_sk,
  COALESCE(cat.category_code, 'UNK')  AS category_code,
  COALESCE(a.agent_sk, -1)            AS assigned_agent_sk,
  t.priority,
  t.status,
  t.created_ts,
  t.resolved_ts,
  CAST((UNIX_SECONDS(CAST(t.resolved_ts AS TIMESTAMP)) - UNIX_SECONDS(CAST(t.created_ts AS TIMESTAMP))) / 60 AS INT64)
                                      AS resolution_minutes,
  (t.resolved_ts IS NOT NULL AND
   UNIX_SECONDS(CAST(t.resolved_ts AS TIMESTAMP)) - UNIX_SECONDS(CAST(t.created_ts AS TIMESTAMP))
     > COALESCE(cat.sla_hours, 24) * 3600)                          AS sla_breached_flag,
  CAST(COALESCE(ev.touches, 0) AS INT64)                            AS touch_count,
  CAST(FORMAT_TIMESTAMP('%Y%m%d', t.created_ts) AS INT64)           AS date_key
FROM ods.ods_ticket_acid t
LEFT JOIN staging.stg_tkt_category cat ON cat.category_id = t.category_id
LEFT JOIN dm.dim_agent a ON a.agent_id = t.assigned_agent_id AND a.is_current = TRUE
LEFT JOIN (
  SELECT e.ticket_id, COUNT(*) AS touches
  FROM staging.stg_tkt_ticket_event e
  GROUP BY e.ticket_id
) ev ON ev.ticket_id = t.ticket_id
WHERE DATE(t.created_ts) = run_date;
