-- 22-cleanse-interaction.sql  [cleanse]  engine=bigquery
-- Converted from Impala to BigQuery Standard SQL.
-- reads:  ods.ods_call, ods.ods_chat_session, ods.ods_email_interaction,
--         staging.stg_file_interaction_export
-- writes: ods.ods_interaction

-- Conform calls + chats + emails into the omnichannel interaction spine.
-- IDs: 'V'<call_id> / 'C'<chat_ref> / 'E'<email_ref>. Client interaction
-- exports (SFTP) are LEFT JOINed for the client-side customer reference.
-- No epoch casting in this script — reads already-cleansed ODS timestamps.
-- unix_timestamp(ts) → UNIX_SECONDS(CAST(ts AS TIMESTAMP));
-- to_date(ts) → DATE(ts).

DECLARE run_date DATE DEFAULT CURRENT_DATE();

DELETE FROM ods.ods_interaction WHERE event_date = run_date;

INSERT INTO ods.ods_interaction
SELECT
  u.interaction_id,
  u.channel,
  u.client_code,
  u.program_id,
  u.queue_id,
  u.agent_id,
  COALESCE(x.customer_ref, u.fallback_customer_ref) AS customer_ref,
  u.start_ts,
  u.end_ts,
  u.handle_seconds,
  u.resolved_flag,
  u.source_system,
  DATE(u.start_ts) AS event_date
FROM (
  SELECT CONCAT('V', CAST(c.call_id AS STRING)) AS interaction_id,
         'VOICE' AS channel, CAST(NULL AS STRING) AS client_code,
         c.program_id, c.queue_id, c.agent_id,
         CAST(NULL AS STRING) AS fallback_customer_ref,
         c.start_ts, c.end_ts,
         c.talk_seconds + c.hold_seconds + c.acw_seconds AS handle_seconds,
         (NOT c.abandoned_flag AND c.talk_seconds > 0)   AS resolved_flag,
         'switch' AS source_system
  FROM ods.ods_call c
  WHERE c.call_date = run_date
  UNION ALL
  SELECT CONCAT('C', ch.chat_ref), 'CHAT', ch.client_code,
         CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
         ch.agent_email,
         ch.started_ts, ch.ended_ts,
         CAST(UNIX_SECONDS(CAST(ch.ended_ts AS TIMESTAMP)) - UNIX_SECONDS(CAST(ch.started_ts AS TIMESTAMP)) AS INT64),
         (ch.message_count > 2), 'chat_feed'
  FROM ods.ods_chat_session ch
  WHERE ch.event_date = run_date
  UNION ALL
  SELECT CONCAT('E', em.email_ref), 'EMAIL', em.client_code,
         CAST(NULL AS INT64), CAST(NULL AS INT64), CAST(NULL AS INT64),
         em.mailbox,
         em.received_ts, em.resolved_ts,
         em.reply_sla_minutes * 60,
         (em.resolved_ts IS NOT NULL), 'email_feed'
  FROM ods.ods_email_interaction em
  WHERE em.event_date = run_date
) u
LEFT JOIN staging.stg_file_interaction_export x
       ON x.interaction_ref = u.interaction_id
      AND x.feed_date = run_date;
