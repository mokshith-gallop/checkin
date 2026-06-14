# BigQuery View Audit Report — Hive→BigQuery Dialect Translation

**Date**: Automated audit (156 checks via `scripts/audit_views.mjs`)  
**Scope**: All 15 DM views in `bigquery/ddl/dm/vw_*.sql`  
**Source**: `/workspace/source/hive/ddl/09-dm-views.hql`  
**Result**: ✅ ALL 15 VIEWS PASS — 156/156 checks passed, 0 issues

---

## Structural Checks (All 15 views)

| Check | Result |
|-------|--------|
| `CREATE VIEW IF NOT EXISTS` (not `CREATE OR REPLACE`) | ✅ PASS |
| Dataset-qualified name (`dm.vw_*`) | ✅ PASS |
| No `USE` statements | ✅ PASS |
| All table references resolve to DDL files | ✅ PASS |
| No remaining Hive-isms in SQL body | ✅ PASS |
| Output column names match source | ✅ PASS |
| 15/15 source views have target views | ✅ PASS |

---

## Translation Checks (Per-view)

### 1. `vw_org_hierarchy` — Recursive CTE
- `WITH RECURSIVE org_tree (col_list) AS` → `WITH RECURSIVE org_tree AS` ✅
- Explicit column list dropped (BigQuery infers from first SELECT) ✅
- `CONCAT()`, `UNION ALL`, depth guard all identical ✅

### 2. `vw_active_agents_ndv` — Approximate Distinct Count
- `NDV(expr)` → `APPROX_COUNT_DISTINCT(expr)` ✅ (2 occurrences)
- `CAST(x AS STRING)` identical in BigQuery ✅

### 3. `vw_csat_rollup` — ROLLUP + GROUPING
- `GROUP BY col1, col2 WITH ROLLUP` → `GROUP BY ROLLUP(col1, col2)` ✅
- `GROUPING__ID` → `GROUPING(p.client_id) * 2 + GROUPING(p.program_code)` ✅
- Bit-order correct: MSB = leftmost GROUP BY column ✅

### 4. `vw_call_driver_regex` — Regex Functions
- `RLIKE 'pattern'` → `REGEXP_CONTAINS(col, r'pattern')` ✅ (3 patterns × 2 = 6 occurrences)
- `regexp_extract(str, pattern, group)` → `REGEXP_EXTRACT(str, r'pattern')` ✅
- HQL double-backslash `\\\\[` → raw string single `\\[` ✅
- `regexp_extract(...) <> ''` → `REGEXP_EXTRACT(...) IS NOT NULL` ✅
- All regex patterns use raw string literals `r'...'` ✅

### 5. `vw_repeat_contact_window` — Epoch Arithmetic
- `unix_timestamp(ts)` → `UNIX_SECONDS(ts)` ✅ (2 occurrences in CASE)
- 259200 constant (72 hours) preserved ✅
- `LAG()` window function syntax identical ✅

### 6. `vw_billing_reconciliation` — Epoch + Lying Column
- `from_unixtime(CAST(... AS BIGINT))` → `TIMESTAMP_SECONDS(CAST(... AS INT64))` ✅
- `unix_timestamp(ts)` → `UNIX_SECONDS(ts)` ✅
- `CAST(x AS BIGINT)` → `CAST(x AS INT64)` ✅
- `/1000` division for lying column preserved ✅
- Cross-layer references (`staging.stg_fin_invoice`, `ods.ods_invoice_acid`) preserved ✅

### 7. `vw_agent_roster_current` — ROW_NUMBER + SCD-2
- No translation needed — syntax identical ✅
- `ROW_NUMBER() OVER (PARTITION BY ... ORDER BY ...)` ✅
- `h.*` subquery select ✅
- `is_current = TRUE` works with BOOL ✅

### 8. `vw_agent_scorecard` — CTEs + Window Functions
- No translation needed — syntax identical ✅
- `PERCENT_RANK()`, `NTILE()`, `COALESCE()` all identical ✅

### 9. `vw_attrition_risk` — Nested CTEs + NTILE Banding
- No translation needed — syntax identical ✅
- Body matches source exactly ✅

### 10. `vw_queue_sla_attainment` — Layer-Skip
- Layer-skip preserved: `staging.stg_crm_sla_target` reference ✅
- No translation needed — syntax identical ✅

### 11. `vw_first_contact_resolution` — Self-Join + Date Arithmetic
- `date_add(f.end_ts, 7)` → `TIMESTAMP_ADD(f.end_ts, INTERVAL 7 DAY)` ✅
- Self-join logic identical ✅

### 12. `vw_occupancy_utilization` — State Pivot
- No translation needed — syntax identical ✅
- `LIKE 'AUX%'`, `NULLIF()`, `SUM(CASE WHEN ...)` all identical ✅

### 13. `vw_shrinkage_analysis` — Date Conversion Chain
- Hive chain: `CAST(from_unixtime(unix_timestamp(CAST(date_key AS STRING), 'yyyyMMdd'), 'yyyy-MM-dd') AS STRING)`
- BigQuery: `PARSE_DATE('%Y%m%d', CAST(f.date_key AS STRING))` ✅
- `sched_date` comparison: DATE = DATE (since `sched_date` is now DATE type) ✅

### 14. `vw_program_margin` — Cross-Join Wart
- No translation needed — syntax identical ✅
- `ON 1 = 1` cross-join wart preserved ✅

### 15. `vw_client_executive_summary` — Hub View
- No translation needed — syntax identical ✅
- All DM-layer references correct ✅

---

## Division Behavior Verification

BigQuery `/` operator returns `FLOAT64` for `INT64 / INT64` operands (unlike some databases which do integer division). Verified via live query:
```sql
SELECT 3 / 10 * 100  -- Returns 30, not 0
```
All `SUM(...) / COUNT(*) * 100` patterns in views produce correct percentage results.

---

## Cross-Layer References

All DM views that read from `ods.*` or `staging.*` tables (layer-skip reads):

| View | Cross-Layer Table | Purpose |
|------|------------------|---------|
| `vw_org_hierarchy` | `ods.ods_org_unit` | Recursive hierarchy |
| `vw_call_driver_regex` | `ods.ods_call` | Call data with disposition join |
| `vw_repeat_contact_window` | `ods.ods_interaction` | Interaction timeline for repeat detection |
| `vw_billing_reconciliation` | `staging.stg_fin_invoice`, `ods.ods_invoice_acid` | Raw epoch comparison |
| `vw_agent_roster_current` | `ods.ods_agent_scd2`, `ods.ods_agent_assignment_scd2` | SCD-2 slice |
| `vw_agent_scorecard` | `ods.ods_agent_skill_scd2` | Certified skills count |
| `vw_attrition_risk` | `ods.ods_attrition_event` | Notice event count |
| `vw_queue_sla_attainment` | `staging.stg_crm_sla_target` | SLA target lookup |
| `vw_shrinkage_analysis` | `ods.ods_schedule` | Schedule join |
| `vw_program_margin` | `ods.ods_timesheet`, `ods.ods_payroll_adjustment`, `ods.ods_contract_line` | Cost proxy |
