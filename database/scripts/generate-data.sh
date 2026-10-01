#!/usr/bin/env bash
# =============================================================================
# (Re)generate the e-commerce dataset with a size profile, then verify it.
#
#   ./scripts/generate-data.sh small        # ~10% of default, < 1 min
#   ./scripts/generate-data.sh default      # ~3.3M rows (same as the first `docker compose up`)
#   ./scripts/generate-data.sh 5m           # ~5M rows per main table (~48M rows in total)
#   ./scripts/generate-data.sh custom       # NUM_* / BATCH_SIZE from .env or the environment
#
#   Options:  -y / --yes      do not ask for confirmation
#             --no-verify     skip ./scripts/verify-data.sh at the end
#
# WARNING: wipes the current data (RESET_DATA=true -> TRUNCATE all data tables).
# The replica follows automatically through streaming replication.
# Same SEED + same DATA_NOW (ISO timestamp) => byte-identical data.
# =============================================================================
. "$(dirname "$0")/lib.sh"

profile=""
assume_yes=0
verify=1
while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes)     assume_yes=1 ;;
    --no-verify)  verify=0 ;;
    -h|--help)    sed -n '2,17p' "$0"; exit 0 ;;
    small|default|5m|custom) profile="$1" ;;
    *) fail "unknown argument: $1 (profiles: small | default | 5m | custom)"; exit 2 ;;
  esac
  shift
done
[ -n "$profile" ] || { sed -n '2,17p' "$0"; exit 2; }

# users products inventory orders order_items reviews batch_size | est. size per node | est. time
case "$profile" in
  small)   set -- 10000    10000    10000    50000    150000   30000   10000 "~100 MB" "< 1 min" ;;
  default) set -- 100000   100000   100000   500000   1500000  300000  10000 "~800 MB" "~1.5 min" ;;
  5m)      set -- 5000000  5000000  5000000  5000000  10000000 5000000 50000 "~13 GB"  "~20 min" ;;
  custom)  set -- "${NUM_USERS:-100000}" "${NUM_PRODUCTS:-100000}" "${NUM_INVENTORY:-100000}" \
                  "${NUM_ORDERS:-500000}" "${NUM_ORDER_ITEMS:-1500000}" "${NUM_REVIEWS:-300000}" \
                  "${BATCH_SIZE:-10000}" "?" "?" ;;
esac
users=$1 products=$2 inventory=$3 orders=$4 items=$5 reviews=$6 batch=$7 est_size=$8 est_time=$9

require_running "$PRIMARY_SERVICE"

header "Profile '$profile'"
printf '  %-14s %12s\n' users "$users" "addresses" "~$(( users * 16 / 10 )) (1-3 per user)" \
  products "$products" inventory "$inventory" orders "$orders" order_items "$items" \
  payments "~$(( orders * 103 / 100 )) (some failed attempts)" reviews "$reviews" batch_size "$batch"
echo "  estimated size: $est_size per node (primary + replica), time: $est_time"
echo "  free space in the Docker VM: $(docker compose exec -T "$PRIMARY_SERVICE" df -h /var/lib/postgresql/data | awk 'NR==2 {print $4}')"
current="$(scalar_on "$PRIMARY_SERVICE" "SELECT count(*) FROM orders")"
echo
warn "this TRUNCATEs the current data ($current orders) on the primary and the replica"
if [ "$assume_yes" -ne 1 ]; then
  read -r -p "Continue? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "aborted"; exit 1; }
fi

header "Generating"
started=$(date +%s)
docker compose run --rm \
  -e RESET_DATA=true \
  -e NUM_USERS="$users" -e NUM_PRODUCTS="$products" -e NUM_INVENTORY="$inventory" \
  -e NUM_ORDERS="$orders" -e NUM_ORDER_ITEMS="$items" -e NUM_REVIEWS="$reviews" \
  -e BATCH_SIZE="$batch" \
  data-generator
ok "generation finished in $(( ($(date +%s) - started) / 60 )) min $(( ($(date +%s) - started) % 60 )) s"

header "Replication after the bulk load"
./scripts/check-replication.sh | grep -E '^\[(OK|FAIL|WARN)\]|lag ' || true

if [ "$verify" -eq 1 ]; then
  ./scripts/verify-data.sh
fi
