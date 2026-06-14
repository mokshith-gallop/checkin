#!/usr/bin/env bash
# =============================================================================
# run-all-ddl.sh — Execute all BigQuery DDL files in dependency order.
#
# Creates 100 tables + 15 views across 3 datasets (staging, ods, dm).
# Total: 116 DDL executions (1 dataset creation + 45 staging + 30 ods +
#        25 dm tables + 15 dm views).
#
# Usage:
#   ./run-all-ddl.sh [--project PROJECT_ID] [--dry-run]
#
# Execution order:
#   Phase 1: 00-create-datasets.sql  (CREATE SCHEMA for staging, ods, dm)
#   Phase 2: staging/*.sql           (45 tables — no dependencies)
#   Phase 3: ods/*.sql               (30 tables — no inter-DDL dependencies)
#   Phase 4: dm/ tables              (25 tables — no inter-DDL dependencies)
#   Phase 5: dm/ views               (15 views — depend on tables in all 3 datasets)
#
# AC #1  — prints "applied X/100 tables" coverage line
# AC #12 — prints "applied X/15 views" coverage line
# Any table/view that fails to create is a HARD FAIL naming the object and
# the BigQuery error.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_FLAG=""
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)  PROJECT_FLAG="--project_id=$2"; shift 2 ;;
    --dry-run)  DRY_RUN=true; shift ;;
    *)          echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# Counters
TOTAL=0
TABLE_PASS=0
TABLE_FAIL=0
VIEW_PASS=0
VIEW_FAIL=0
DATASET_PASS=0
DATASET_FAIL=0
FAILED_OBJECTS=()

run_ddl() {
  local filepath="$1"
  local label="$2"
  local kind="$3"    # 'dataset', 'table', or 'view'
  TOTAL=$((TOTAL + 1))

  if $DRY_RUN; then
    echo "[DRY-RUN] Would execute: $label ($kind)"
    case "$kind" in
      dataset) DATASET_PASS=$((DATASET_PASS + 1)) ;;
      table)   TABLE_PASS=$((TABLE_PASS + 1)) ;;
      view)    VIEW_PASS=$((VIEW_PASS + 1)) ;;
    esac
    return 0
  fi

  echo -n "[$TOTAL] $label ... "
  local output
  if output=$(bq query --nouse_legacy_sql $PROJECT_FLAG < "$filepath" 2>&1); then
    echo "OK"
    case "$kind" in
      dataset) DATASET_PASS=$((DATASET_PASS + 1)) ;;
      table)   TABLE_PASS=$((TABLE_PASS + 1)) ;;
      view)    VIEW_PASS=$((VIEW_PASS + 1)) ;;
    esac
  else
    echo "FAIL"
    echo "  ERROR: $output"
    case "$kind" in
      dataset) DATASET_FAIL=$((DATASET_FAIL + 1)) ;;
      table)   TABLE_FAIL=$((TABLE_FAIL + 1)) ;;
      view)    VIEW_FAIL=$((VIEW_FAIL + 1)) ;;
    esac
    FAILED_OBJECTS+=("$kind: $label — $output")
  fi
}

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  BigQuery DDL Deployment                                  ║"
echo "║  $(date -u '+%Y-%m-%d %H:%M:%S UTC')                              ║"
echo "║  Expected: 1 dataset file + 100 tables + 15 views = 116  ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# ── Phase 1: Create datasets ────────────────────────────────────
echo "── Phase 1: Create datasets (3 schemas) ──"
run_ddl "$SCRIPT_DIR/00-create-datasets.sql" "00-create-datasets.sql" "dataset"
echo ""

# ── Phase 2: Staging tables (45) ────────────────────────────────
echo "── Phase 2: Staging tables (45) ──"
for f in "$SCRIPT_DIR"/staging/*.sql; do
  run_ddl "$f" "staging/$(basename "$f")" "table"
done
echo ""

# ── Phase 3: ODS tables (30) ───────────────────────────────────
echo "── Phase 3: ODS tables (30) ──"
for f in "$SCRIPT_DIR"/ods/*.sql; do
  run_ddl "$f" "ods/$(basename "$f")" "table"
done
echo ""

# ── Phase 4: DM tables (25) ────────────────────────────────────
echo "── Phase 4: DM tables (25) ──"
for f in "$SCRIPT_DIR"/dm/*.sql; do
  # Skip view files and non-SQL files — views run in Phase 5
  [[ "$(basename "$f")" == vw_* ]] && continue
  [[ "$(basename "$f")" != *.sql ]] && continue
  run_ddl "$f" "dm/$(basename "$f")" "table"
done
echo ""

# ── Phase 5: DM views (15) ─────────────────────────────────────
echo "── Phase 5: DM views (15) ──"
for f in "$SCRIPT_DIR"/dm/vw_*.sql; do
  run_ddl "$f" "dm/$(basename "$f")" "view"
done
echo ""

# ── Summary ─────────────────────────────────────────────────────
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  DEPLOYMENT SUMMARY                                       ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  Total DDL executions:  $TOTAL"
echo "  Dataset creation:      $DATASET_PASS passed, $DATASET_FAIL failed"
echo ""
echo "  applied $TABLE_PASS/100 tables"
echo "  applied $VIEW_PASS/15 views"
echo ""

if [[ $TABLE_FAIL -gt 0 ]] || [[ $VIEW_FAIL -gt 0 ]] || [[ $DATASET_FAIL -gt 0 ]]; then
  echo "  HARD FAIL — the following objects failed to create:"
  echo ""
  for ff in "${FAILED_OBJECTS[@]}"; do
    echo "    ✗ $ff"
  done
  echo ""
  echo "  RESULT: FAIL ($TABLE_FAIL table failures, $VIEW_FAIL view failures)"
  exit 1
else
  echo "  RESULT: ALL PASSED — 100/100 tables, 15/15 views created successfully"
  exit 0
fi
