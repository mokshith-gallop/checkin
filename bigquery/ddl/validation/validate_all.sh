#!/usr/bin/env bash
# =============================================================================
# validate_all.sh — Run all acceptance-criteria validation SQL scripts.
#
# Covers:
#   AC #1  — Column count parity (100 tables)
#   AC #2  — Epoch encoding types & descriptions
#   AC #3  — ACID tables (native, nullable, no ORC)
#   AC #4  — Identifier legality (names, reserved words)
#   AC #5  — SCD-2 surrogate keys (STRING + MD5)
#   AC #6  — DECIMAL precision (NUMERIC, 7 distinct pairs)
#   AC #7  — Format provenance (BASE TABLE + description)
#   AC #8  — Complex types (ARRAY/STRUCT/JSON recursive)
#   AC #9  — Nullability (no NULLABLE→REQUIRED)
#   AC #10 — Partition type legality (no STRING partitions)
#   AC #11 — Comment preservation (68 Hive COMMENTs)
#
# Usage:
#   ./validate_all.sh [--project PROJECT_ID]
#
# Each script is run via `bq query --nouse_legacy_sql`. The output is printed
# to stdout and the exit code is captured. A consolidated PASS/FAIL summary
# is printed at the end.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_FLAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)  PROJECT_FLAG="--project_id=$2"; shift 2 ;;
    *)          echo "Unknown arg: $1"; exit 1 ;;
  esac
done

TOTAL=0
PASS=0
FAIL=0
RESULTS=()

run_check() {
  local sql_file="$1"
  local label="$2"
  TOTAL=$((TOTAL + 1))

  echo "============================================================"
  echo "AC Check: $label"
  echo "  File: $sql_file"
  echo "============================================================"

  if bq query --nouse_legacy_sql --format=prettyjson $PROJECT_FLAG < "$sql_file" 2>&1; then
    echo ""
    echo "  → Result: OK (query executed successfully)"
    PASS=$((PASS + 1))
    RESULTS+=("  ✓ $label")
  else
    echo ""
    echo "  → Result: QUERY ERROR"
    FAIL=$((FAIL + 1))
    RESULTS+=("  ✗ $label")
  fi
  echo ""
}

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  BigQuery DDL Validation — Acceptance Criteria Checks     ║"
echo "║  $(date -u '+%Y-%m-%d %H:%M:%S UTC')                              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Core schema checks
run_check "$SCRIPT_DIR/check_column_counts.sql"         "AC #1  — Column count parity (100 tables)"
run_check "$SCRIPT_DIR/check_epoch_types.sql"            "AC #2  — Epoch encoding types & descriptions"
run_check "$SCRIPT_DIR/check_acid_tables.sql"            "AC #3  — ACID tables (native, nullable, no ORC)"
run_check "$SCRIPT_DIR/check_identifiers.sql"            "AC #4  — Identifier legality (checked X/Y)"
run_check "$SCRIPT_DIR/check_scd2_keys.sql"              "AC #5  — SCD-2 surrogate keys (STRING + MD5)"
run_check "$SCRIPT_DIR/check_decimal_precision.sql"      "AC #6  — DECIMAL precision (checked X/Y DECIMAL columns)"
run_check "$SCRIPT_DIR/check_format_tables.sql"          "AC #7  — Format provenance (BASE TABLE + description)"
run_check "$SCRIPT_DIR/check_complex_types.sql"          "AC #8  — Complex types (ARRAY/STRUCT/JSON recursive)"
run_check "$SCRIPT_DIR/check_nullability.sql"            "AC #9  — Nullability (checked X/Y, no REQUIRED)"
run_check "$SCRIPT_DIR/check_partition_types.sql"        "AC #10 — Partition type legality (no STRING partitions)"
run_check "$SCRIPT_DIR/check_comment_preservation.sql"   "AC #11 — Comment preservation (preserved X/Y)"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  CONSOLIDATED SUMMARY                                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  Total checks: $TOTAL"
echo "  Executed OK:  $PASS"
echo "  Query errors: $FAIL"
echo ""
for r in "${RESULTS[@]}"; do
  echo "$r"
done
echo ""

if [[ $FAIL -eq 0 ]]; then
  echo "  OVERALL: ALL $TOTAL QUERIES EXECUTED SUCCESSFULLY"
  echo "  (Review individual query output above for PASS/FAIL per row)"
  exit 0
else
  echo "  OVERALL: $FAIL QUERY ERRORS — review output above"
  exit 1
fi
