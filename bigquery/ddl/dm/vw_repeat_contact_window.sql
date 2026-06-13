-- bigquery/ddl/dm/vw_repeat_contact_window.sql
-- Converted from Hive/Impala DDL to BigQuery Standard SQL.
--
-- Source (Hive): 09-dm-views.hql — view #5
-- Trap: LAG window function + raw epoch arithmetic via unix_timestamp().
--
-- Conversion notes:
--   - Hive unix_timestamp(ts) → BigQuery UNIX_SECONDS(ts).
--     Both convert TIMESTAMP to epoch seconds (INT64).
--   - 259200 seconds = 72 hours (3 days) — unchanged.
--   - LAG() window function syntax is identical in BigQuery.

CREATE VIEW IF NOT EXISTS dm.vw_repeat_contact_window AS
SELECT i.interaction_id,
       i.customer_ref,
       i.channel,
       i.start_ts,
       LAG(i.start_ts) OVER (PARTITION BY i.customer_ref ORDER BY i.start_ts) AS prev_contact_ts,
       CASE WHEN UNIX_SECONDS(i.start_ts)
               - UNIX_SECONDS(LAG(i.start_ts) OVER (PARTITION BY i.customer_ref
                                                     ORDER BY i.start_ts)) <= 259200
            THEN 1 ELSE 0 END                            AS repeat_within_72h
FROM   ods.ods_interaction i
WHERE  i.customer_ref IS NOT NULL AND i.customer_ref <> '';
