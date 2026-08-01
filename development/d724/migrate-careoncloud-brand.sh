#!/usr/bin/env bash
# CareOnCloud ESM enterprise service management platform.
# GPL-3.0-or-later. See LICENSE and NOTICE.

set -Eeuo pipefail

usage() {
    cat <<'USAGE'
Usage:
  migrate-careoncloud-brand.sh [options]

Options:
  --execute                    Perform the migration. Without it, print the plan only.
  --compose-file PATH          Compose file (default: development/d724/compose.yml).
  --env-file PATH              Environment file containing D724_DB_ROOT_PASSWORD.
  --old-app-volume NAME        Existing application volume (required with --execute).
  --old-update-volume NAME     Existing update volume (optional).
  --new-app-volume NAME        New volume (default: d724-esm_careoncloud-app).
  --new-update-volume NAME     New volume (default: d724-esm_careoncloud-update).
  --old-database NAME          Existing database (default: otobo).
  --new-database NAME          New database (default: careoncloud_esm).
  --new-db-user NAME           New database user (default: careoncloud_esm).
  --new-db-password VALUE      New database password (required with --execute).
  --backup-dir PATH            Backup directory (default: ./careoncloud-migration-backup-TIMESTAMP).
  --help                       Show this help.

The migration is copy-only: old volumes and the old database are never deleted.
USAGE
}

ComposeFile='development/d724/compose.yml'
EnvFile=''
OldAppVolume=''
OldUpdateVolume=''
NewAppVolume='d724-esm_careoncloud-app'
NewUpdateVolume='d724-esm_careoncloud-update'
OldDatabase='otobo'
NewDatabase='careoncloud_esm'
NewDBUser='careoncloud_esm'
NewDBPassword=''
printf -v MigrationTimestamp '%(%Y%m%dT%H%M%SZ)T' -1
BackupDir="careoncloud-migration-backup-$MigrationTimestamp"
Execute=0

while (( $# )); do
    case "$1" in
        --execute) Execute=1; shift ;;
        --compose-file) ComposeFile="$2"; shift 2 ;;
        --env-file) EnvFile="$2"; shift 2 ;;
        --old-app-volume) OldAppVolume="$2"; shift 2 ;;
        --old-update-volume) OldUpdateVolume="$2"; shift 2 ;;
        --new-app-volume) NewAppVolume="$2"; shift 2 ;;
        --new-update-volume) NewUpdateVolume="$2"; shift 2 ;;
        --old-database) OldDatabase="$2"; shift 2 ;;
        --new-database) NewDatabase="$2"; shift 2 ;;
        --new-db-user) NewDBUser="$2"; shift 2 ;;
        --new-db-password) NewDBPassword="$2"; shift 2 ;;
        --backup-dir) BackupDir="$2"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

compose() {
    local Args=( compose --file "$ComposeFile" )
    if [[ -n "$EnvFile" ]]; then
        Args+=( --env-file "$EnvFile" )
    fi
    docker "${Args[@]}" "$@"
}

require_name() {
    local Kind="$1" Value="$2"
    if [[ ! "$Value" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
        echo "Invalid $Kind: $Value" >&2
        exit 2
    fi
}

require_secret() {
    local Value="$1"
    if [[ ! "$Value" =~ ^[A-Za-z0-9_.@%+=:-]+$ ]]; then
        echo 'The database password may contain only letters, numbers and _ . @ % + = : - for this migration tool.' >&2
        exit 2
    fi
}

for Pair in \
    "new app volume:$NewAppVolume" \
    "new update volume:$NewUpdateVolume" \
    "old database:$OldDatabase" \
    "new database:$NewDatabase" \
    "new database user:$NewDBUser"
do
    require_name "${Pair%%:*}" "${Pair#*:}"
done

cat <<PLAN
CareOnCloud ESM brand migration plan
  compose file      : $ComposeFile
  old app volume    : ${OldAppVolume:-<must be supplied for execution>}
  old update volume : ${OldUpdateVolume:-<not copied>}
  new app volume    : $NewAppVolume
  new update volume : $NewUpdateVolume
  database          : $OldDatabase -> $NewDatabase
  database user     : $NewDBUser
  backup directory  : $BackupDir
PLAN

if (( ! Execute )); then
    echo 'Dry run only. Re-run with --execute and the required credentials after reviewing this plan.'
    exit 0
fi

command -v docker >/dev/null || { echo 'docker is required.' >&2; exit 1; }
docker compose version >/dev/null
[[ -f "$ComposeFile" ]] || { echo "Compose file not found: $ComposeFile" >&2; exit 1; }
[[ -n "$OldAppVolume" ]] || { echo '--old-app-volume is required with --execute.' >&2; exit 2; }
[[ -n "$NewDBPassword" ]] || { echo '--new-db-password is required with --execute.' >&2; exit 2; }
require_secret "$NewDBPassword"
require_name 'old app volume' "$OldAppVolume"
if [[ -n "$OldUpdateVolume" ]]; then
    require_name 'old update volume' "$OldUpdateVolume"
fi

docker volume inspect "$OldAppVolume" >/dev/null
if [[ -n "$OldUpdateVolume" ]]; then
    docker volume inspect "$OldUpdateVolume" >/dev/null
fi

mkdir -p "$BackupDir"
chmod 700 "$BackupDir"

echo 'Stopping application writers while keeping the database available...'
compose stop web daemon

echo 'Creating a logical database backup...'
compose exec -T db sh -lc \
    'exec mariadb-dump --single-transaction --routines --events -uroot -p"$MYSQL_ROOT_PASSWORD" --databases "$1"' \
    sh "$OldDatabase" >"$BackupDir/${OldDatabase}.sql"
test -s "$BackupDir/${OldDatabase}.sql"

echo 'Creating CareOnCloud volumes...'
docker volume create "$NewAppVolume" >/dev/null
docker volume create "$NewUpdateVolume" >/dev/null

copy_volume() {
    local Source="$1" Target="$2"
    docker run --rm \
        --mount "type=volume,src=$Source,dst=/source,readonly" \
        --mount "type=volume,src=$Target,dst=/target" \
        alpine:3.22 sh -euc 'cd /source && tar -cf - . | tar -xpf - -C /target'
}

echo 'Copying application data to the CareOnCloud volume...'
copy_volume "$OldAppVolume" "$NewAppVolume"
if [[ -n "$OldUpdateVolume" ]]; then
    echo 'Copying update data to the CareOnCloud update volume...'
    copy_volume "$OldUpdateVolume" "$NewUpdateVolume"
fi

echo 'Creating and importing the CareOnCloud database...'
compose exec -T db sh -lc \
    'exec mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS \`$1\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; CREATE USER IF NOT EXISTS \`$2\`@\`%\` IDENTIFIED BY \"$3\"; ALTER USER \`$2\`@\`%\` IDENTIFIED BY \"$3\"; GRANT ALL PRIVILEGES ON \`$1\`.* TO \`$2\`@\`%\`; FLUSH PRIVILEGES;"' \
    sh "$NewDatabase" "$NewDBUser" "$NewDBPassword"

compose exec -T db sh -lc \
    'mariadb-dump --single-transaction --routines --events -uroot -p"$MYSQL_ROOT_PASSWORD" "$1" | exec mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" "$2"' \
    sh "$OldDatabase" "$NewDatabase"

echo 'Renaming legacy product-specific schema objects in the copied database...'
compose exec -T db sh -lc \
    'TableExists="$(mariadb -N -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=\"$1\" AND table_name=\"article_data_otobo_chat\"")"; if [ "$TableExists" = 1 ]; then exec mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" -e "RENAME TABLE \`$1\`.\`article_data_otobo_chat\` TO \`$1\`.\`article_data_careoncloud_chat\`"; fi' \
    sh "$NewDatabase"

OldTableCount="$(compose exec -T db sh -lc \
    'exec mariadb -N -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=\"$1\""' \
    sh "$OldDatabase" | tr -d '\r')"
NewTableCount="$(compose exec -T db sh -lc \
    'exec mariadb -N -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=\"$1\""' \
    sh "$NewDatabase" | tr -d '\r')"

if [[ -z "$OldTableCount" || "$OldTableCount" != "$NewTableCount" || "$NewTableCount" == 0 ]]; then
    echo "Database verification failed: old=$OldTableCount new=$NewTableCount" >&2
    exit 1
fi

cat >"$BackupDir/migration-result.txt" <<RESULT
status=copy-complete
old_database=$OldDatabase
new_database=$NewDatabase
table_count=$NewTableCount
old_app_volume=$OldAppVolume
new_app_volume=$NewAppVolume
old_update_volume=$OldUpdateVolume
new_update_volume=$NewUpdateVolume
RESULT

echo "Copy migration completed and verified ($NewTableCount tables)."
echo "Old data remains intact. Update application configuration, deploy, and run acceptance tests before removing anything."
echo "Result: $BackupDir/migration-result.txt"
