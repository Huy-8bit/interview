#!/usr/bin/env bash
# Lab 18 — large messages: client limit, broker/topic limit, raising the limit, chunking.
source "$(dirname "$0")/../lib.sh"
T=large-messages
existing="$(kt kafka-topics --bootstrap-server "$BOOTSTRAP_INTERNAL" --list 2>/dev/null)"
grep -qx "$T" <<<"$existing" || kt kafka-topics --bootstrap-server "$BOOTSTRAP_INTERNAL" --create --topic $T --partitions 3 --replication-factor 3 --config min.insync.replicas=2 >/dev/null
kt kafka-configs --bootstrap-server "$BOOTSTRAP_INTERNAL" --alter --entity-type topics --entity-name $T --delete-config max.message.bytes >/dev/null 2>&1 || true
sleep 1
kt kafka-configs --bootstrap-server "$BOOTSTRAP_INTERNAL" --describe --all --entity-type topics --entity-name $T 2>/dev/null | grep -oE "max.message.bytes=[0-9]+" | head -1

banner "1. 2 MB record, producer batch.max.bytes = 1 MB -> rejected BY THE CLIENT (never sent)"
r1="$(kcli large-message -topic $T -size 2MB -mode single -client-max-batch 1MB)"; echo "$r1"
expect "client-side rejection" bash -c "echo '$r1' | grep -q FAILED"

banner "2. Raise the client limit to 10 MB -> rejected BY THE BROKER (topic max.message.bytes ~1 MB)"
r2="$(kcli large-message -topic $T -size 2MB -mode single -client-max-batch 10MB)"; echo "$r2"
expect "broker rejects with MESSAGE_TOO_LARGE" bash -c "echo '$r2' | grep -qiE 'MESSAGE_TOO_LARGE|too large'"

banner "3. Raise the TOPIC limit to 5 MB (max.message.bytes) -> accepted"
kt kafka-configs --bootstrap-server "$BOOTSTRAP_INTERNAL" --alter --entity-type topics --entity-name $T --add-config max.message.bytes=5242880 2>/dev/null
sleep 2
r3="$(kcli large-message -topic $T -size 2MB -mode single -client-max-batch 10MB)"; echo "$r3"
expect "2 MB record accepted after raising max.message.bytes" bash -c "echo '$r3' | grep -q 'OK:'"
step "consumers still read it: a fetch always returns at least the first batch, even if > fetch.max.bytes (KIP-74)"
kcli consume -topic $T -from start -idle 3s -summary

banner "4. Chunking alternative: 3 MB split into 256 KB records, same key -> same partition -> reassembled in order"
kt kafka-configs --bootstrap-server "$BOOTSTRAP_INTERNAL" --alter --entity-type topics --entity-name $T --delete-config max.message.bytes >/dev/null 2>&1
sleep 2
r4="$(kcli large-message -topic $T -size 3MB -mode chunked -chunk 256KB)"; echo "$r4"
expect "chunks reassembled with matching sha256" bash -c "echo '$r4' | grep -q 'sha256 match=true'"
lab_done
