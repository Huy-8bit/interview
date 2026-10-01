#!/usr/bin/env bash
# =============================================================================
# Run the query-optimization labs end to end and prove that every reset works.
#
# For each lab folder in sql/optimization/NN_*:
#   05_reset (pre-clean) -> baseline check
#   01_before -> 02_optimize -> 03_after -> 04_compare -> 05_reset [-> 06_verify_reset]
#   -> baseline check (must be "BASELINE OK") -> 01_before again (must still run)
# For each challenge: challenge_NN.sql -> solutions/solution_NN.sql -> baseline check.
#
#   ./scripts/test-optimization-labs.sh                 # all labs + challenges
#   ./scripts/test-optimization-labs.sh 01 05 16        # only labs whose number matches
#   ./scripts/test-optimization-labs.sh challenges      # only the challenges
#
# Every file runs in its OWN psql session (like opening it in a new DBeaver editor),
# so a lab must not rely on session state (SET ...) carried over from another file.
# Logs (full EXPLAIN output): sql/optimization/.runs/<lab>/<file>.log
# =============================================================================
. "$(dirname "$0")/lib.sh"

LAB_ROOT="sql/optimization"
LOG_ROOT="$LAB_ROOT/.runs"
require_running "$PRIMARY_SERVICE"

filters=("$@")
run_labs=1 run_challenges=1
if [ ${#filters[@]} -gt 0 ]; then
  run_challenges=0
  for f in "${filters[@]}"; do [ "$f" = "challenges" ] && run_challenges=1; done
  only_challenges=1
  for f in "${filters[@]}"; do [ "$f" != "challenges" ] && only_challenges=0; done
  [ "$only_challenges" -eq 1 ] && run_labs=0
fi

run_sql() {   # run_sql <file> <log>  -> 0/1, wall seconds in $elapsed
  local file="$1" log="$2" start
  start=$(date +%s)
  if docker compose exec -T "$PRIMARY_SERVICE" psql -X -q -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
       -f /dev/stdin < "$file" > "$log" 2>&1; then
    elapsed=$(( $(date +%s) - start )); return 0
  fi
  elapsed=$(( $(date +%s) - start )); return 1
}

baseline_ok() {   # baseline_ok <log>
  run_sql "$LAB_ROOT/00_environment/09_verify_baseline.sql" "$1" || return 1
  grep -q "BASELINE OK" "$1"
}

passed=0 failed=0
declare -a summary

test_lab() {
  local dir="$1" name log_dir step status="PASS" note="" total=0
  name="$(basename "$dir")"
  log_dir="$LOG_ROOT/$name"
  mkdir -p "$log_dir"
  printf '%-34s ' "$name"

  if ! run_sql "$dir/05_reset.sql" "$log_dir/00_pre_reset.log"; then status="FAIL"; note="pre-reset failed"; fi
  if [ "$status" = PASS ] && ! baseline_ok "$log_dir/00_pre_baseline.log"; then status="FAIL"; note="not at baseline before start"; fi

  if [ "$status" = PASS ]; then
    for step in 01_before 02_optimize 03_after 04_compare 05_reset 06_verify_reset; do
      [ -f "$dir/$step.sql" ] || continue
      if run_sql "$dir/$step.sql" "$log_dir/$step.log"; then
        total=$(( total + elapsed )); printf '%s:%ss ' "${step%%_*}" "$elapsed"
      else
        status="FAIL"; note="$step.sql failed (see $log_dir/$step.log)"; break
      fi
    done
  fi
  if [ "$status" = PASS ] && ! baseline_ok "$log_dir/07_baseline_after_reset.log"; then
    status="FAIL"; note="reset left changes: $(grep -v -E '^\s*$|kind|---|rows?\)' "$log_dir/07_baseline_after_reset.log" | head -3 | tr -s ' ' | tr '\n' ';')"
  fi
  # Labs working on their own lab_* table create it in 01_before.sql: every strategy starts from there
  local needs_before=0 strat sname steps
  grep -q 'DROP TABLE IF EXISTS lab_' "$dir/05_reset.sql" && needs_before=1
  # Strategy B, C, ...: each one applied alone on the baseline, then reset again
  for strat in "$dir"/02[b-z]_*.sql; do
    [ "$status" = PASS ] && [ -f "$strat" ] || continue
    sname="$(basename "$strat" .sql)"
    steps=("$strat" "$dir/03_after.sql" "$dir/05_reset.sql")
    [ "$needs_before" -eq 1 ] && steps=("$dir/01_before.sql" "${steps[@]}")
    for step in "${steps[@]}"; do
      if run_sql "$step" "$log_dir/${sname}__$(basename "$step" .sql).log"; then total=$(( total + elapsed ))
      else status="FAIL"; note="$sname: $(basename "$step") failed (see $log_dir/${sname}__$(basename "$step" .sql).log)"; break; fi
    done
    if [ "$status" = PASS ] && ! baseline_ok "$log_dir/${sname}__baseline.log"; then
      status="FAIL"; note="$sname: reset left changes"
    fi
    [ "$status" = PASS ] && printf '%s:ok ' "${sname%%_*}"
  done
  # The lab must still run after its reset, and leave nothing behind afterwards
  if [ "$status" = PASS ]; then
    if run_sql "$dir/01_before.sql" "$log_dir/08_before_again.log"; then printf 'rerun:%ss ' "$elapsed"
    else status="FAIL"; note="01_before.sql failed after reset"; fi
  fi
  if [ "$status" = PASS ]; then
    run_sql "$dir/05_reset.sql" "$log_dir/09_final_reset.log" || { status="FAIL"; note="final reset failed"; }
  fi
  if [ "$status" = PASS ] && ! baseline_ok "$log_dir/10_final_baseline.log"; then
    status="FAIL"; note="final reset left changes"
  fi

  if [ "$status" = PASS ]; then echo "${C_GREEN}PASS${C_RESET} (${total}s)"; passed=$((passed + 1))
  else echo "${C_RED}FAIL${C_RESET} $note"; failed=$((failed + 1))
       run_sql "$LAB_ROOT/00_environment/99_reset_all_labs.sql" "$log_dir/99_emergency_reset.log" || true
  fi
  summary+=("$status $name $note")
}

test_challenge() {
  local file="$1" num name sol log_dir status="PASS" note=""
  name="$(basename "$file" .sql)"; num="${name#challenge_}"
  sol="$LAB_ROOT/99_challenges/solutions/solution_$num.sql"
  log_dir="$LOG_ROOT/99_challenges"; mkdir -p "$log_dir"
  printf '%-34s ' "$name"
  if ! run_sql "$file" "$log_dir/$name.log"; then status="FAIL"; note="challenge failed"
  elif [ ! -f "$sol" ]; then status="FAIL"; note="missing $sol"
  elif ! run_sql "$sol" "$log_dir/solution_$num.log"; then status="FAIL"; note="solution failed (see $log_dir/solution_$num.log)"
  elif ! baseline_ok "$log_dir/solution_${num}_baseline.log"; then status="FAIL"; note="solution did not reset"
  fi
  if [ "$status" = PASS ]; then echo "${C_GREEN}PASS${C_RESET}"; passed=$((passed + 1))
  else echo "${C_RED}FAIL${C_RESET} $note"; failed=$((failed + 1))
       run_sql "$LAB_ROOT/00_environment/99_reset_all_labs.sql" "$log_dir/99_emergency_reset.log" || true
  fi
  summary+=("$status $name $note")
}

header "Optimization labs  (logs: $LOG_ROOT/)"
mkdir -p "$LOG_ROOT"
if [ "$run_labs" -eq 1 ]; then
  for dir in "$LAB_ROOT"/[0-9][0-9]_*/; do
    dir="${dir%/}"; base="$(basename "$dir")"
    case "$base" in 00_*|99_*) continue ;; esac
    if [ ${#filters[@]} -gt 0 ]; then
      match=0; for f in "${filters[@]}"; do [ "${base%%_*}" = "$f" ] && match=1; done
      [ "$match" -eq 1 ] || continue
    fi
    test_lab "$dir"
  done
fi
if [ "$run_challenges" -eq 1 ]; then
  header "Challenges"
  for file in "$LAB_ROOT"/99_challenges/challenge_*.sql; do
    [ -f "$file" ] && test_challenge "$file"
  done
fi

echo
if [ "$failed" -eq 0 ]; then ok "$passed passed, 0 failed - database is at baseline"
else fail "$passed passed, $failed failed"; printf '  %s\n' "${summary[@]}" | grep '^FAIL'; exit 1; fi
