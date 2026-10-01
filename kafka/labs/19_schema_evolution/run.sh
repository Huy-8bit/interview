#!/usr/bin/env bash
# Lab 19 — schema evolution with Schema Registry (Avro compatibility rules) + the wire format.
source "$(dirname "$0")/../lib.sh"
SR=localhost:8081
S=orders-avro-value
DIR="$(cd "$(dirname "$0")" && pwd)/schemas"
payload() { python3 -c 'import json,sys; print(json.dumps({"schemaType": sys.argv[2], "schema": open(sys.argv[1]).read()}))' "$1" "${2:-AVRO}"; }
compat() { curl -s -X POST -H 'Content-Type: application/vnd.schemaregistry.v1+json' --data "$(payload "$DIR/$1")" "$SR/compatibility/subjects/$S/versions/latest?verbose=true"; }
register() { curl -s -X POST -H 'Content-Type: application/vnd.schemaregistry.v1+json' --data "$(payload "$DIR/$1" "${2:-AVRO}")" "$SR/subjects/${3:-$S}/versions"; }
set_level() { curl -s -X PUT -H 'Content-Type: application/vnd.schemaregistry.v1+json' --data "{\"compatibility\":\"$1\"}" "$SR/config/$S"; echo; }
is_compat() { compat "$1" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("is_compatible")); [print("    reason:", m[:160]) for m in d.get("messages",[])[:2]]'; }

curl -s -X DELETE "$SR/subjects/$S" >/dev/null; curl -s -X DELETE "$SR/subjects/$S?permanent=true" >/dev/null

banner "1. Register v1 (subject $S, compatibility BACKWARD = new readers can read old data)"
set_level BACKWARD
register order-v1.avsc; echo

banner "2. v2: add OPTIONAL field coupon (default null)"
r="$(is_compat order-v2-add-optional.avsc)"; echo "BACKWARD compatible? $r"
expect "adding a field WITH default is backward compatible" test "$(echo "$r" | head -1)" = True
register order-v2-add-optional.avsc; echo

banner "3. v3: add REQUIRED field currency (no default)"
r="$(is_compat order-v3-add-required.avsc)"; echo "BACKWARD compatible? $r"
expect "adding a field WITHOUT default breaks BACKWARD (new reader has no value for old records)" test "$(echo "$r" | head -1)" = False

banner "4. v3: change quantity int -> string"
r="$(is_compat order-v3-quantity-string.avsc)"; echo "BACKWARD compatible? $r"
expect "type change is incompatible" test "$(echo "$r" | head -1)" = False

banner "5. v3: REMOVE quantity (no default) — BACKWARD ok, FORWARD not"
r="$(is_compat order-v3-remove-quantity.avsc)"; echo "BACKWARD compatible? $r"
expect "removing a field is backward compatible (new reader ignores it)" test "$(echo "$r" | head -1)" = True
set_level FORWARD
r="$(is_compat order-v3-remove-quantity.avsc)"; echo "FORWARD compatible?  $r"
expect "...but not FORWARD: old readers require quantity and it has no default" test "$(echo "$r" | head -1)" = False
set_level FULL
r="$(is_compat order-v3-remove-quantity.avsc)"; echo "FULL compatible?     $r"
set_level BACKWARD

banner "6. Versions stored in the registry (in the _schemas topic)"
curl -s "$SR/subjects/$S/versions"; echo
curl -s "$SR/subjects/$S/versions/2" | python3 -c 'import sys,json; d=json.load(sys.stdin); print("subject", d["subject"], "version", d["version"], "id", d["id"])'

banner "7. Wire format: JSON Schema subject + record = [magic 0x00][schema id 4B][payload]"
existing="$(kt kafka-topics --bootstrap-server "$BOOTSTRAP_INTERNAL" --list 2>/dev/null)"
grep -qx orders-sr <<<"$existing" || kt kafka-topics --bootstrap-server "$BOOTSTRAP_INTERNAL" --create --topic orders-sr --partitions 3 --replication-factor 3 >/dev/null
register order-v1.schema.json JSON orders-sr-value; echo
out="$(kcli sr-produce -subject orders-sr-value -topic orders-sr)"; echo "$out"
expect "record produced with the registry wire format" bash -c "echo '$out' | grep -q 'first bytes=00 00'"
echo "Open Kafka UI > Topics > orders-sr > Messages: the value is decoded through Schema Registry."
lab_done
