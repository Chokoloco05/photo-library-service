#!/bin/sh
set -eu

export REPLICATION_PASSWORD="$(cat /run/replication/password)"
psql -X -U photo -d postgres -v ON_ERROR_STOP=1 <<'SQL'
SELECT pg_advisory_lock(726043);
DO $$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'photo_replicator') THEN
        CREATE ROLE photo_replicator WITH LOGIN REPLICATION;
    END IF;
END $$;
\getenv replication_password REPLICATION_PASSWORD
SELECT format('ALTER ROLE photo_replicator WITH LOGIN REPLICATION NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD %L', :'replication_password') \gexec
SELECT pg_create_physical_replication_slot('photo_standby')
WHERE NOT EXISTS (SELECT FROM pg_replication_slots WHERE slot_name = 'photo_standby');
SELECT pg_advisory_unlock(726043);
SQL
unset REPLICATION_PASSWORD

rule='host replication photo_replicator all scram-sha-256'
if ! grep -Fqx "$rule" "$PGDATA/pg_hba.conf"; then
    printf '\n%s\n' "$rule" >> "$PGDATA/pg_hba.conf"
fi
psql -X -U photo -d postgres -v ON_ERROR_STOP=1 -c 'SELECT pg_reload_conf();'
