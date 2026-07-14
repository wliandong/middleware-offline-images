#!/usr/bin/env bash
set -euo pipefail

app_database="${MYSQL_DATABASE:-appdb}"
app_user="${MYSQL_USER:?MYSQL_USER is required}"
app_password="${MYSQL_PASSWORD:?MYSQL_PASSWORD is required}"

sql_escape() {
  printf '%s' "$1" | sed "s/'/''/g"
}

database_sql="$(sql_escape "$app_database")"
user_sql="$(sql_escape "$app_user")"
password_sql="$(sql_escape "$app_password")"

mysql --protocol=socket -uroot -p"${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD is required}" <<SQL
CREATE DATABASE IF NOT EXISTS `${database_sql}` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE USER IF NOT EXISTS '${user_sql}'@'%' IDENTIFIED BY '${password_sql}';
GRANT ALL PRIVILEGES ON `${database_sql}`.* TO '${user_sql}'@'%';
FLUSH PRIVILEGES;
SQL
