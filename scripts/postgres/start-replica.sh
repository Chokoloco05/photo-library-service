#!/bin/sh
set -eu
: "${PRIMARY_HOST:=photo-db}"

# The primary data directory is mounted only in its own StatefulSet.
if [ "$PGDATA" != '/var/lib/postgresql/data/replica' ]; then
    echo 'Unexpected replica data directory.' >&2
    exit 1
fi
if [ "$(id -u)" = '0' ]; then
    mkdir -p /var/lib/postgresql/data
    chown postgres:postgres /var/lib/postgresql/data
    exec gosu postgres sh /opt/replication/start-replica.sh
fi
umask 077
printf '%s:5432:replication:photo_replicator:%s\n' "$PRIMARY_HOST" "$(cat /run/replication/password)" > /tmp/replication.pgpass
export PGPASSFILE=/tmp/replication.pgpass

if [ ! -f "$PGDATA/PG_VERSION" ]; then
    # Each attempt uses a fresh staging directory. A failed copy is never started.
    staging=$(mktemp -d /var/lib/postgresql/data/basebackup.XXXXXX)
    trap 'rm -rf -- "$staging"' EXIT
    pg_basebackup --dbname="host=$PRIMARY_HOST port=5432 user=photo_replicator application_name=photo-db-replica passfile=/tmp/replication.pgpass" \
        --pgdata="$staging" --wal-method=stream --checkpoint=fast \
        --write-recovery-conf --slot=photo_standby --no-password
    pg_verifybackup "$staging"
    if [ -e "$PGDATA" ]; then
        echo 'Incomplete replica data directory requires inspection.' >&2
        exit 1
    fi
    mv "$staging" "$PGDATA"
    trap - EXIT
fi
if [ ! -f "$PGDATA/standby.signal" ]; then
    echo 'Replica is not in standby mode. Inspect its timeline before restarting.' >&2
    exit 1
fi
exec postgres -D "$PGDATA" -c hot_standby=on
