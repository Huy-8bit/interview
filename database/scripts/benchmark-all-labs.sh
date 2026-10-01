#!/usr/bin/env bash
# =============================================================================
# Benchmark every optimization lab, one after the other.
# Wrapper around scripts/benchmark-optimization-lab.sh.
#
#   ./scripts/benchmark-all-labs.sh                 # labs 01..41, 3 timed runs per query
#   ./scripts/benchmark-all-labs.sh --runs 5        # 5 timed runs per query
#   ./scripts/benchmark-all-labs.sh 05 16 21        # only these labs
#
# A failing lab does not stop the others. At the end:
#   * the list of labs that failed
#   * one CSV with the results of all labs: sql/optimization/.runs/bench/all_<UTC time>.csv
#   * the full screen output of each lab:    sql/optimization/.runs/bench/all_<UTC time>/<lab>.log
#
# Long: the database is busy for a long time (indexes created/dropped on tables of
# 5-10M rows, slow baseline queries run several times). Do not run it while data is loaded.
# =============================================================================
set -uo pipefail
cd "$(dirname "$0")/.."

runs=3
labs=()
while [ $# -gt 0 ]; do
  case "$1" in
    --runs)    runs="$2"; shift ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    [0-9][0-9]) labs+=("$1") ;;
    *) echo "unknown argument: $1"; exit 2 ;;
  esac
  shift
done
[ ${#labs[@]} -gt 0 ] || labs=($(seq -w 1 41))

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out_dir="sql/optimization/.runs/bench/all_$stamp"
all_csv="sql/optimization/.runs/bench/all_$stamp.csv"
mkdir -p "$out_dir"

failed=()
started=$(date +%s)
total=${#labs[@]}
i=0
for n in "${labs[@]}"; do
  i=$((i + 1))
  echo "===== [$i/$total] lab $n  ($(( ($(date +%s) - started) / 60 )) min elapsed) ====="
  log="$out_dir/$n.log"
  if ./scripts/benchmark-optimization-lab.sh "$n" --runs "$runs" 2>&1 | tee "$log"; then
    csv="$(grep -oE 'sql/optimization/\.runs/bench/[^ ]+\.csv' "$log" | tail -1)"
    if [ -n "$csv" ] && [ -f "$csv" ]; then
      [ -f "$all_csv" ] || head -1 "$csv" > "$all_csv"
      tail -n +2 "$csv" >> "$all_csv"
    fi
  else
    echo "Lab $n FAILED (see $log)"
    failed+=("$n")
  fi
done

echo
echo "===== done in $(( ($(date +%s) - started) / 60 )) min: $((total - ${#failed[@]})) ok, ${#failed[@]} failed ====="
[ ${#failed[@]} -gt 0 ] && echo "failed labs: ${failed[*]}  (logs in $out_dir/)"
[ -f "$all_csv" ] && echo "all results: $all_csv"
echo "per-lab output: $out_dir/"
[ ${#failed[@]} -eq 0 ]
