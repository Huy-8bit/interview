#!/usr/bin/env bash
# =============================================================================
# Measure one optimization lab: the same queries BEFORE and AFTER each strategy,
# N timed runs each, median / min / max + buffers, then a comparison table.
#
#   ./scripts/benchmark-optimization-lab.sh 05                 # before + every strategy, 5 runs each
#   ./scripts/benchmark-optimization-lab.sh 05 --runs 10       # 10 timed runs per query
#   ./scripts/benchmark-optimization-lab.sh 05 --strategy b    # before + strategy B only (a, b, c...)
#   ./scripts/benchmark-optimization-lab.sh 05 --list          # print the queries to be measured (no database)
#
# How it measures
#   * Queries are taken from the lab files themselves: every
#     "EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)" / "EXPLAIN (ANALYZE, BUFFERS, WAL, VERBOSE)"
#     block of 01_before.sql (before), 03_after.sql (after a strategy that changes the
#     database) or of the strategy file itself (experiments with their own queries / SETs).
#     "EXPLAIN ONLY" queries are never executed.
#   * Each query runs 1 + N times inside a temporary function (pg_temp, gone at the end of
#     the session) via EXPLAIN (ANALYZE, BUFFERS, WAL, TIMING OFF, FORMAT JSON). Every run
#     is rolled back (so INSERT/UPDATE/DELETE never change data). The first run warms the
#     cache and is reported separately; median / min / max use the N other runs.
#   * Execution Time excludes sending rows to the client.
#   * Order: 05_reset -> baseline check -> before -> (strategy -> measure -> 05_reset ->
#     baseline check) for each strategy. The database ends at BASELINE OK.
#
# Not a lab-correctness test (that is scripts/test-optimization-labs.sh). Do not run it
# while data is being loaded: it creates/drops indexes and the numbers would be noise.
# Results: table on screen + CSV in sql/optimization/.runs/bench/<lab>_<UTC time>.csv
# =============================================================================
. "$(dirname "$0")/lib.sh"

LAB_ROOT="sql/optimization"
runs=5
only_strategy=""
list_only=0
lab=""
while [ $# -gt 0 ]; do
  case "$1" in
    --runs)     runs="$2"; shift ;;
    --strategy) only_strategy="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"; shift ;;
    --list)     list_only=1 ;;
    -h|--help)  sed -n '2,27p' "$0"; exit 0 ;;
    [0-9][0-9]) lab="$1" ;;
    *) fail "unknown argument: $1"; exit 2 ;;
  esac
  shift
done
[ -n "$lab" ] || { sed -n '2,10p' "$0"; exit 2; }
[[ "$runs" =~ ^[0-9]+$ ]] && [ "$runs" -ge 1 ] || { fail "--runs must be a positive integer"; exit 2; }

dir="$(ls -d "$LAB_ROOT"/"$lab"_*/ 2>/dev/null | head -1 || true)"; dir="${dir%/}"
[ -n "$dir" ] && [ -f "$dir/01_before.sql" ] || { fail "lab $lab not found in $LAB_ROOT"; exit 2; }
lab_name="$(basename "$dir")"

work="$(mktemp -d "${TMPDIR:-/tmp}/bench.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# ---- extract the measurable queries of a lab file into <out>/q<N>.{sql,setup,title} ----
extract() {   # extract <sql file> <out dir>  -> prints the number of queries
  mkdir -p "$2"
  awk -v out="$2" '
    function emit() {
      qi++
      sub(/;[ \t]*\n$/, "\n", q)
      printf "%s", q     > (out "/q" qi ".sql");   close(out "/q" qi ".sql")
      printf "%s", setup > (out "/q" qi ".setup"); close(out "/q" qi ".setup")
      printf "%s\n", title > (out "/q" qi ".title"); close(out "/q" qi ".title")
    }
    # query block header: dashes / "-- Qn. title" / dashes
    /^-- -+$/ && length($0) > 40 { if (hdr == 2) hdr = 0; else { hdr = 1; setup = "" }; next }
    hdr == 1 { title = $0; sub(/^-- /, "", title); sub(/^Q[0-9]+\. /, "", title); hdr = 2; next }
    !cap && /^SET / { setup = setup $0 "\n"; next }
    $0 == "EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)" || $0 == "EXPLAIN (ANALYZE, BUFFERS, WAL, VERBOSE)" { cap = 1; q = ""; next }
    cap { q = q $0 "\n"; if ($0 ~ /;[ \t]*$/) { cap = 0; emit() }; next }
    END { print qi + 0 }
  ' "$1"
}

# ---- variants: before, then one per strategy ---------------------------------------------
variants=()   # entries: name|apply_file|query_source
variants+=("before||$dir/01_before.sql")
for f in "$dir"/02_optimize.sql "$dir"/02[b-z]_*.sql; do
  [ -f "$f" ] || continue
  base="$(basename "$f")"
  if [ "$base" = "02_optimize.sql" ]; then letter="a"; else letter="${base:2:1}"; fi
  [ -n "$only_strategy" ] && [ "$letter" != "$only_strategy" ] && continue
  # strategies whose file says "Next: run 05_reset.sql" carry their own queries (experiments)
  if grep -q 'Next: run 05_reset.sql' "$f"; then src="$f"; else src="$dir/03_after.sql"; fi
  variants+=("strategy $(printf '%s' "$letter" | tr '[:lower:]' '[:upper:]')|$f|$src")
done
[ ${#variants[@]} -gt 1 ] || { fail "no strategy matches --strategy $only_strategy"; exit 2; }

for i in "${!variants[@]}"; do
  IFS='|' read -r vname _apply vsrc <<< "${variants[$i]}"
  n="$(extract "$vsrc" "$work/v$i")"
  echo "$n" > "$work/v$i/count"
done

if [ "$list_only" -eq 1 ]; then
  header "$lab_name: queries that would be measured ($runs runs each)"
  for i in "${!variants[@]}"; do
    IFS='|' read -r vname vapply vsrc <<< "${variants[$i]}"
    echo; echo "${C_BOLD}[$vname]${C_RESET}  apply: ${vapply:-(baseline)}   queries from: $vsrc"
    for ((q = 1; q <= $(cat "$work/v$i/count"); q++)); do
      echo "  Q$q  $(cat "$work/v$i/q$q.title")"
      [ -s "$work/v$i/q$q.setup" ] && sed 's/^/        setup: /' "$work/v$i/q$q.setup"
      sed 's/^/        /' "$work/v$i/q$q.sql"
    done
  done
  exit 0
fi

# ---- database helpers ---------------------------------------------------------------------
require_running "$PRIMARY_SERVICE"
log_dir="$LAB_ROOT/.runs/bench"; mkdir -p "$log_dir"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
csv="$log_dir/${lab_name}_${stamp}.csv"
echo "lab,variant,query,title,top_node,rows,median_ms,min_ms,max_ms,warmup_ms,planning_ms,shared_hit,shared_read,temp_blocks,wal_bytes,runs" > "$csv"

run_file() {   # run_file <sql file> <log>
  docker compose exec -T "$PRIMARY_SERVICE" psql -X -q -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
    -f /dev/stdin < "$1" > "$2" 2>&1
}
baseline_ok() {
  run_file "$LAB_ROOT/00_environment/09_verify_baseline.sql" "$work/baseline.log" && grep -q "BASELINE OK" "$work/baseline.log"
}
needs_before=0
grep -q 'DROP TABLE IF EXISTS lab_' "$dir/05_reset.sql" && needs_before=1

BENCH_FN="$(cat <<'SQL'
CREATE FUNCTION pg_temp.bench(q text, n int)
RETURNS TABLE (run int, exec_ms float8, plan_ms float8, hit bigint, rd bigint, tmp bigint, wal bigint,
               act_rows float8, node text)
LANGUAGE plpgsql AS $fn$
DECLARE p json;
BEGIN
  FOR i IN 0..n LOOP
    BEGIN
      EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, WAL, TIMING OFF, FORMAT JSON) ' || q INTO p;
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'bench: roll back this run';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN NULL;   -- PL/pgSQL variables survive the rollback
    END;
    run      := i;
    exec_ms  := (p->0->>'Execution Time')::float8;
    plan_ms  := (p->0->>'Planning Time')::float8;
    hit      := (p->0->'Plan'->>'Shared Hit Blocks')::bigint;
    rd       := (p->0->'Plan'->>'Shared Read Blocks')::bigint;
    tmp      := coalesce((p->0->'Plan'->>'Temp Read Blocks')::bigint, 0)
              + coalesce((p->0->'Plan'->>'Temp Written Blocks')::bigint, 0);
    wal      := coalesce((p->0->'Plan'->>'WAL Bytes')::bigint, 0);
    act_rows := (p->0->'Plan'->>'Actual Rows')::float8;
    node     := p->0->'Plan'->>'Node Type';
    RETURN NEXT;
  END LOOP;
END $fn$;
SQL
)"

measure() {   # measure <variant index> <query n>  -> one '|'-separated summary line
  local d="$work/v$1" f="$work/m_$1_$2.sql"
  {
    echo "$BENCH_FN"
    cat "$d/q$2.setup"
    printf 'WITH r AS (SELECT * FROM pg_temp.bench($bq$\n'
    cat "$d/q$2.sql"
    printf '$bq$, %d))\n' "$runs"
    cat <<'SQL'
SELECT max(node),
       max(act_rows)::bigint,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY exec_ms)::numeric, 3),
       round(min(exec_ms)::numeric, 3),
       round(max(exec_ms)::numeric, 3),
       round((SELECT exec_ms FROM r WHERE run = 0)::numeric, 3),
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY plan_ms)::numeric, 3),
       percentile_disc(0.5) WITHIN GROUP (ORDER BY hit),
       percentile_disc(0.5) WITHIN GROUP (ORDER BY rd),
       max(tmp),
       max(wal)
FROM r WHERE run > 0;
SQL
  } > "$f"
  docker compose exec -T "$PRIMARY_SERVICE" psql -X -q -tA -F'|' -v ON_ERROR_STOP=1 \
    -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /dev/stdin < "$f" 2> "$work/m_$1_$2.err" | tail -1 || true
}

# ---- run ----------------------------------------------------------------------------------
header "Benchmark $lab_name  ($runs timed runs + 1 warm-up per query, database $POSTGRES_DB)"
run_file "$dir/05_reset.sql" "$work/pre_reset.log" || { fail "05_reset.sql failed: $(tail -3 "$work/pre_reset.log")"; exit 1; }
baseline_ok || { fail "database is not at baseline - see sql/optimization/00_environment/09_verify_baseline.sql"; cat "$work/baseline.log"; exit 1; }

for i in "${!variants[@]}"; do
  IFS='|' read -r vname vapply vsrc <<< "${variants[$i]}"
  if [ "$needs_before" -eq 1 ]; then
    printf '  %-12s creating the lab table (01_before.sql)... ' "$vname"
    run_file "$dir/01_before.sql" "$work/setup_$i.log" || { echo; fail "01_before.sql failed"; tail -5 "$work/setup_$i.log"; exit 1; }
    echo "done"
  fi
  if [ -n "$vapply" ]; then
    printf '  %-12s applying %s... ' "$vname" "$(basename "$vapply")"
    run_file "$vapply" "$work/apply_$i.log" || { echo; fail "$(basename "$vapply") failed"; tail -5 "$work/apply_$i.log"
                                                run_file "$dir/05_reset.sql" "$work/reset_$i.log"; exit 1; }
    echo "done"
  fi
  for ((q = 1; q <= $(cat "$work/v$i/count"); q++)); do
    printf '  %-12s Q%d %s ... ' "$vname" "$q" "$(cut -c1-60 "$work/v$i/q$q.title")"
    line="$(measure "$i" "$q")"
    if [ -z "$line" ]; then
      echo "${C_RED}error${C_RESET}"; sed 's/^/      /' "$work/m_${i}_$q.err" | head -5
      run_file "$dir/05_reset.sql" "$work/reset_$i.log"; exit 1
    fi
    echo "$line" > "$work/r_${i}_$q"
    IFS='|' read -r node rows med mn mx warm plan hit rd tmp wal <<< "$line"
    echo "median ${med} ms"
    title="$(sed 's/"/""/g' "$work/v$i/q$q.title")"
    echo "$lab_name,$vname,$q,\"$title\",$node,$rows,$med,$mn,$mx,$warm,$plan,$hit,$rd,$tmp,$wal,$runs" >> "$csv"
  done
  if [ -n "$vapply" ] || [ "$needs_before" -eq 1 ]; then
    run_file "$dir/05_reset.sql" "$work/reset_$i.log" || { fail "05_reset.sql failed"; exit 1; }
    baseline_ok || { fail "reset of $vname left changes"; cat "$work/baseline.log"; exit 1; }
  fi
done

# ---- report -------------------------------------------------------------------------------
fmt_ms() { awk -v v="$1" 'BEGIN { if (v == "") print "-"; else if (v < 10) printf "%.3f", v; else printf "%.1f", v }'; }
before_count="$(cat "$work/v0/count")"
max_q=0
for i in "${!variants[@]}"; do c="$(cat "$work/v$i/count")"; [ "$c" -gt "$max_q" ] && max_q="$c"; done

header "Results: $lab_name  (median of $runs runs; 'warm-up' = first run, not in the median)"
for ((q = 1; q <= max_q; q++)); do
  echo
  printf '%sQ%d%s\n' "$C_BOLD" "$q" "$C_RESET"
  printf '  %-11s %-44s %-24s %9s %12s %18s %9s %10s %10s %8s %12s %9s\n' \
    variant query "top node" rows "median ms" "min..max ms" "warm-up" "plan ms" "sh. hit" "sh. read" "temp/WAL B" speedup
  for i in "${!variants[@]}"; do
    [ -f "$work/r_${i}_$q" ] || continue
    IFS='|' read -r vname _a _s <<< "${variants[$i]}"
    IFS='|' read -r node rows med mn mx warm plan hit rd tmp wal < "$work/r_${i}_$q"
    speed="-"
    if [ "$i" -gt 0 ] && [ -f "$work/r_0_$q" ]; then
      bmed="$(cut -d'|' -f3 "$work/r_0_$q")"
      speed="$(awk -v b="$bmed" -v a="$med" 'BEGIN { if (a > 0) printf "%.1fx", b / a; else print "-" }')"
    fi
    printf '  %-11s %-44.44s %-24.24s %9s %12s %18s %9s %10s %10s %8s %12s %9s\n' \
      "$vname" "$(cat "$work/v$i/q$q.title")" "$node" "$rows" "$(fmt_ms "$med")" "$(fmt_ms "$mn")..$(fmt_ms "$mx")" \
      "$(fmt_ms "$warm")" "$(fmt_ms "$plan")" "$hit" "$rd" "$tmp/$wal" "$speed"
  done
done
echo
echo "speedup = median(before Qn) / median(variant Qn). Compare the 'query' column first: a variant may"
echo "measure a rewritten query or an experiment with different queries (then the ratio is only indicative)."
echo "shared read = pages PostgreSQL had to ask the OS for (OS page cache or disk); hit = already in shared_buffers."
ok "CSV: $csv"
ok "database is back at baseline"
