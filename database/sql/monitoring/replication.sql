-- =============================================================================
-- Replication monitoring. Open in DBeaver and run statement by statement
-- (Ctrl+Enter). Each section says where to run it: PRIMARY (5432) or REPLICA (5433).
-- Running a [PRIMARY] query on the replica (or vice versa) fails ON PURPOSE, e.g.
--   pg_current_wal_lsn() on a replica  -> ERROR: recovery is in progress
--   pg_last_wal_replay_lsn() on the primary -> NULL, pg_is_wal_replay_paused() -> ERROR
-- Metric explanations: docs/replication.md, section "Monitoring".
-- =============================================================================

-- -----------------------------------------------------------------------------
-- [BOTH] Which node am I on?
-- -----------------------------------------------------------------------------
SELECT current_setting('cluster_name') AS node,
       pg_is_in_recovery()             AS is_replica,
       inet_server_addr()              AS server_ip,
       now()                           AS server_time;

-- -----------------------------------------------------------------------------
-- [PRIMARY] Connected standbys: one row per walsender process
-- -----------------------------------------------------------------------------
SELECT pid,                       -- walsender process on the primary
       application_name,          -- replica's cluster_name
       client_addr,
       state,                     -- startup | catchup | streaming | backup | stopping
       sync_state,                -- async | potential | sync | quorum
       sent_lsn,                  -- last WAL position sent over TCP
       write_lsn,                 -- replica wrote it to its OS (not yet fsync'ed)
       flush_lsn,                 -- replica fsync'ed it to disk (durable there)
       replay_lsn,                -- replica applied it (visible to queries there)
       write_lag, flush_lag, replay_lag,   -- time-based lag (NULL when idle)
       reply_time
FROM pg_stat_replication;

-- -----------------------------------------------------------------------------
-- [PRIMARY] Lag in BYTES per stage
-- -----------------------------------------------------------------------------
SELECT application_name,
       pg_current_wal_lsn()                                                   AS primary_lsn,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn))        AS not_yet_sent,
       pg_size_pretty(pg_wal_lsn_diff(sent_lsn, write_lsn))                   AS sent_not_written,
       pg_size_pretty(pg_wal_lsn_diff(write_lsn, flush_lsn))                  AS written_not_flushed,
       pg_size_pretty(pg_wal_lsn_diff(flush_lsn, replay_lsn))                 AS flushed_not_replayed,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn))      AS total_replay_lag
FROM pg_stat_replication;

-- -----------------------------------------------------------------------------
-- [PRIMARY] Replication slots and how much WAL each one pins on disk
-- wal_status: reserved (fine) | extended (beyond max_wal_size) | unreserved (at risk) | lost (replica must be rebuilt)
-- -----------------------------------------------------------------------------
SELECT slot_name, slot_type, active, active_pid,
       restart_lsn,                                    -- oldest WAL the slot still needs
       wal_status,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal,
       pg_size_pretty(safe_wal_size)                  AS safe_wal_size  -- WAL that can still be written before the slot is invalidated
FROM pg_replication_slots;

-- -----------------------------------------------------------------------------
-- [PRIMARY] Current WAL position and WAL file
-- -----------------------------------------------------------------------------
SELECT pg_current_wal_lsn()                       AS current_lsn,        -- written to WAL buffers
       pg_current_wal_insert_lsn()                AS insert_lsn,         -- reserved for insertion
       pg_current_wal_flush_lsn()                 AS flush_lsn,          -- fsync'ed to disk
       pg_walfile_name(pg_current_wal_lsn())      AS current_wal_file,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0')) AS total_wal_generated_since_initdb;

-- -----------------------------------------------------------------------------
-- [REPLICA] WAL receiver status
-- -----------------------------------------------------------------------------
SELECT pid, status, sender_host, sender_port, slot_name,
       receive_start_lsn, written_lsn, flushed_lsn,
       latest_end_lsn, latest_end_time,          -- last position reported by the primary
       last_msg_send_time, last_msg_receipt_time
FROM pg_stat_wal_receiver;

-- -----------------------------------------------------------------------------
-- [REPLICA] Receive vs replay position and time-based delay
-- -----------------------------------------------------------------------------
SELECT pg_is_in_recovery()                        AS in_recovery,
       pg_last_wal_receive_lsn()                  AS receive_lsn,        -- received + flushed by walreceiver
       pg_last_wal_replay_lsn()                   AS replay_lsn,         -- applied by the startup process
       pg_size_pretty(pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn())) AS receive_replay_gap,
       pg_last_xact_replay_timestamp()            AS last_replayed_commit_time,
       CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN interval '0'
            ELSE now() - pg_last_xact_replay_timestamp()
       END                                         AS replay_delay,
       pg_is_wal_replay_paused()                  AS replay_paused;

-- -----------------------------------------------------------------------------
-- [REPLICA] Queries cancelled because of replay conflicts (per database)
-- -----------------------------------------------------------------------------
SELECT datname, confl_tablespace, confl_lock, confl_snapshot, confl_bufferpin, confl_deadlock
FROM pg_stat_database_conflicts
WHERE datname = current_database();

-- -----------------------------------------------------------------------------
-- [REPLICA] Recovery settings in effect
-- -----------------------------------------------------------------------------
SELECT name, setting, source
FROM pg_settings
WHERE name IN ('hot_standby', 'hot_standby_feedback', 'primary_conninfo', 'primary_slot_name',
               'max_standby_streaming_delay', 'wal_receiver_status_interval', 'recovery_min_apply_delay');
