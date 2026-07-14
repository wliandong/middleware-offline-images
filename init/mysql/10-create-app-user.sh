#!/usr/bin/env bash
set -euo pipefail

app_database="${MYSQL_DATABASE:-appdb}"
app_user="${MYSQL_USER:?MYSQL_USER is required}"
app_password="${MYSQL_PASSWORD:?MYSQL_PASSWORD is required}"

require_identifier() {
  if [[ ! "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    printf 'Invalid SQL identifier: %s\n' "$1" >&2
    exit 1
  fi
}

sql_escape() {
  printf '%s' "$1" | sed "s/'/''/g"
}

require_identifier "$app_database"
require_identifier "$app_user"
password_sql="$(sql_escape "$app_password")"

sql="$(printf "CREATE DATABASE IF NOT EXISTS \`%s\` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;\nCREATE USER IF NOT EXISTS '%s'@'%%' IDENTIFIED BY '%s';\nGRANT ALL PRIVILEGES ON \`%s\`.* TO '%s'@'%%';\nFLUSH PRIVILEGES;\n" "$app_database" "$app_user" "$password_sql" "$app_database" "$app_user")"
printf '%s' "$sql" | mysql --protocol=socket -uroot -p"${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD is required}"
