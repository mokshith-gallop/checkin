#!/usr/bin/env bash
# =============================================================================
# run-all-ddl.sh — Execute all BigQuery DDL files in dependency order.
#
# Usage:
#   ./run-all-ddl.sh [--project PROJECT_ID] [--dry-run]
#
# Execution order:
#   1. 00-create-datasets.sql  (create 3 datasets)
#   2. staging/*.sql           (45 tables — no dependencies)
#   3. ods/*.sql               (30 tables — no inter-DDL dependencies)
#   4. dm/ tables              (25 tables — no inter-DDL dependencies)
#   5. dm/ views               (15 views — depend on tables in all 3 datasets)
#
# Total: 115 DDL files (100 tables + 15 views)
# =============================================================================
set -euo pipefail

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
PASS=0
FAIL=0
FAILED_FILES=()

run_ddl() {
  local filepath="$1"
  local label="$2"
  TOTAL=$((TOTAL + 1))

  if $DRY_RUN; then
    echo "[DRY-RUN] Would execute: $label"
    PASS=$((PASS + 1))
    return 0
  fi

  echo -n "[$TOTAL] $label ... "
  if bq query --nouse_legacy_sql $PROJECT_FLAG --batch < "$filepath" 2>/dev/null; then
    echo "OK"
    PASS=$((PASS + 1))
  else
    echo "FAIL"
    FAIL=$((FAIL + 1))
    FAILED_FILES+=("$label")
  fi
}

echo "============================================================"
echo "BigQuery DDL Deployment — $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "============================================================"
echo ""

# ── Phase 1: Create datasets ────────────────────────────────────
echo "── Phase 1: Create datasets ──"
run_ddl "$SCRIPT_DIR/00-create-datasets.sql" "00-create-datasets.sql"
echo ""

# ── Phase 2: Staging tables (45) ────────────────────────────────
echo "── Phase 2: Staging tables (45) ──"
for f in "$SCRIPT_DIR"/staging/*.sql; do
  run_ddl "$f" "staging/$(basename "$f")"
done
echo ""

# ── Phase 3: ODS tables (30) ───────────────────────────────────
echo "── Phase 3: ODS tables (30) ──"
for f in "$SCRIPT_DIR"/ods/*.sql; do
  run_ddl "$f" "ods/$(basename "$f")"
done
echo ""

# ── Phase 4: DM tables (25) ────────────────────────────────────
echo "── Phase 4: DM tables (25) ──"
for f in "$SCRIPT_DIR"/dm/*.sql; do
  # Skip view files — they run in Phase 5
  [[ "$(basename "$f")" == vw_* ]] && continue
  run_ddl "$f" "dm/$(basename "$f")"
done
echo ""

# ── Phase 5: DM views (15) ─────────────────────────────────────
echo "── Phase 5: DM views (15) ──"
for f in "$SCRIPT_DIR"/dm/vw_*.sql; do
  run_ddl "$f" "dm/$(basename "$f")"
done
echo ""

# ── Summary ─────────────────────────────────────────────────────
echo "============================================================"
echo "SUMMARY"
echo "============================================================"
echo "  Total:  $TOTAL"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
if [[ $FAIL -gt 0 ]]; then
  echo ""
  echo "  Failed files:"
  for ff in "${FAILED_FILES[@]}"; do
    echo "    ✗ $ff"
  done
  echo ""
  echo "RESULT: FAIL"
  exit 1
else
  echo ""
  echo "RESULT: ALL PASSED"
  exit 0
fi
