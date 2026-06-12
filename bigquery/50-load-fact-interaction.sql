-- 50-load-fact-interaction.sql  [fact]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  ods.ods_interaction, dm.dim_agent, dm.dim_program, dm.dim_queue, dm.dim_client
-- writes: dm.fact_interaction

-- Daily partition-scoped INSERT into the interaction fact.
-- Design decision: replaces legacy (date_key, channel) multi-column partition
-- with date_key partition + channel, agent_sk as clustering keys.
-- from_unixtime(unix_timestamp(ts), 'yyyyMMdd') → CAST(FORMAT_TIMESTAMP('%Y%m%d', ts) AS INT64).

DECLARE run_date DATE DEFAULT CURRENT_DATE();
DECLARE date_key_val INT64 DEFAULT CAST(FORMAT_DATE('%Y%m%d', run_date) AS INT64);

DELETE FROM dm.fact_interaction WHERE date_key = date_key_val;

INSERT INTO dm.fact_interaction
SELECT
  i.interaction_id,
  COALESCE(c.client_sk, -1)         AS client_sk,
  COALESCE(p.program_sk, -1)        AS program_sk,
  COALESCE(q.queue_sk, -1)          AS queue_sk,
  COALESCE(a.agent_sk, -1)          AS agent_sk,
  i.customer_ref,
  i.start_ts,
  i.end_ts,
  i.handle_seconds,
  i.resolved_flag,
  i.source_system,
  CAST(FORMAT_TIMESTAMP('%Y%m%d', i.start_ts) AS INT64) AS date_key,
  i.channel
FROM ods.ods_interaction i
LEFT JOIN dm.dim_agent   a ON a.agent_id = i.agent_id AND a.is_current = TRUE
LEFT JOIN dm.dim_program p ON p.program_id = i.program_id
LEFT JOIN dm.dim_queue   q ON q.queue_id = i.queue_id
LEFT JOIN dm.dim_client  c ON c.client_code = i.client_code
WHERE i.event_date = run_date;
