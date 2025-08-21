#!/usr/bin/env bash
# force-root-pass.sh
# Force-set MySQL/MariaDB root password to a hard-coded value.
# Compatible with MySQL 5.7/8.0 and MariaDB (WSL/Ubuntu).
# Comments are in English.

set -Eeuo pipefail

# ===== EDIT THIS VALUE (the password you will set) =====
NEWPASS="MyRootPass!2025"
# =======================================================

DEBIAN_CNF="/etc/mysql/debian.cnf"
DEFAULT_SOCKET="/var/run/mysqld/mysqld.sock"

info()  { printf "\033[1;34m[i]\033[0m %s\n" "$*"; }
ok()    { printf "\033[1;32m[✓]\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err()   { printf "\033[1;31m[×]\033[0m %s\n" "$*" >&2; }
die()   { err "$*"; exit 1; }

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    die "Run this script with sudo (root privileges)."
  fi
}

get_socket() {
  # Try to read socket from /etc/mysql/debian.cnf, fallback to default.
  if [[ -f "$DEBIAN_CNF" ]]; then
    local s
    s="$(awk -F'=' '/socket/ {gsub(/[ \t]/,"",$2); print $2; exit}' "$DEBIAN_CNF" || true)"
    [[ -n "${s:-}" ]] && echo "$s" && return 0
  fi
  echo "$DEFAULT_SOCKET"
}

service_start() { service mysql start  >/dev/null 2>&1 || true; }
service_stop()  { service mysql stop   >/dev/null 2>&1 || true; [[ -x /etc/init.d/mysql ]] && /etc/init.d/mysql stop >/dev/null 2>&1 || true; }

test_maint_login() {
  mysql --defaults-file="$DEBIAN_CNF" --socket="$SOCKET" -e "SELECT 1;" >/dev/null 2>&1
}

server_id() {
  # Returns "mysql" or "mariadb" (best-effort) and prints version info.
  local out
  out="$(mysql --defaults-file="$DEBIAN_CNF" --socket="$SOCKET" -N -e "SELECT @@version, @@version_comment;" 2>/dev/null || true)"
  if [[ "$out" == *"MariaDB"* ]]; then
    echo "mariadb"
  else
    echo "mysql"
  fi
}

# --- Try multiple methods to set password (covers MySQL & MariaDB) ---
set_root_password_multi() {
  local ESCAPED="${NEWPASS//\'/\'\'}"

  # 1) Preferred modern way (MySQL 5.7+/8.0 and MariaDB 10.4+)
  if mysql --defaults-file="$DEBIAN_CNF" --socket="$SOCKET" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${ESCAPED}'; FLUSH PRIVILEGES;" >/dev/null 2>&1; then
    ok "ALTER USER succeeded."
    return 0
  fi
  warn "ALTER USER failed; trying SET PASSWORD ..."

  # 2) Older syntax (works on MySQL 5.6/5.7 and MariaDB)
  if mysql --defaults-file="$DEBIAN_CNF" --socket="$SOCKET" -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${ESCAPED}'); FLUSH PRIVILEGES;" >/dev/null 2>&1; then
    ok "SET PASSWORD succeeded."
    return 0
  fi
  warn "SET PASSWORD failed; trying direct table update ..."

  # 3) Last resort: direct table update (old servers)
  #    MySQL 5.7+: column is 'authentication_string'; older: 'password'
  if mysql --defaults-file="$DEBIAN_CNF" --socket="$SOCKET" -e "UPDATE mysql.user SET authentication_string=PASSWORD('${ESCAPED}') WHERE user='root' AND host='localhost'; FLUSH PRIVILEGES;" >/dev/null 2>&1; then
    ok "UPDATE mysql.user (authentication_string) succeeded."
    return 0
  fi
  if mysql --defaults-file="$DEBIAN_CNF" --socket="$SOCKET" -e "UPDATE mysql.user SET password=PASSWORD('${ESCAPED}') WHERE user='root' AND host='localhost'; FLUSH PRIVILEGES;" >/dev/null 2>&1; then
    ok "UPDATE mysql.user (password) succeeded."
    return 0
  fi

  return 1
}

# --- Fallback path using --skip-grant-tables (no auth) ---
start_skip_grants() {
  nohup mysqld_safe --skip-grant-tables --skip-networking >/tmp/mysqld_safe.log 2>&1 &
  # Wait up to 30s for socket to appear
  for i in $(seq 1 30); do
    [[ -S "$SOCKET" ]] && return 0
    sleep 1
  done
  return 1
}

stop_skip_grants() {
  pkill -f mysqld_safe >/dev/null 2>&1 || true
  pkill -f "[m]ysqld.*skip-grant-tables" >/dev/null 2>&1 || true
  pkill mysqld >/dev/null 2>&1 || true
}

set_root_password_skip_grants() {
  local ESCAPED="${NEWPASS//\'/\'\'}"
  # Try same cascade inside skip-grants (ALTER -> SET PASSWORD -> UPDATE)
  if mysql --protocol=socket --socket="$SOCKET" -u root -e "FLUSH PRIVILEGES; ALTER USER 'root'@'localhost' IDENTIFIED BY '${ESCAPED}'; FLUSH PRIVILEGES;" >/dev/null 2>&1; then
    ok "ALTER USER succeeded in skip-grant mode."
    return 0
  fi
  if mysql --protocol=socket --socket="$SOCKET" -u root -e "FLUSH PRIVILEGES; SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${ESCAPED}'); FLUSH PRIVILEGES;" >/dev/null 2>&1; then
    ok "SET PASSWORD succeeded in skip-grant mode."
    return 0
  fi
  if mysql --protocol=socket --socket="$SOCKET" -u root -e "FLUSH PRIVILEGES; UPDATE mysql.user SET authentication_string=PASSWORD('${ESCAPED}') WHERE user='root' AND host='localhost'; FLUSH PRIVILEGES;" >/dev/null 2>&1; then
    ok "UPDATE (authentication_string) succeeded in skip-grant mode."
    return 0
  fi
  if mysql --protocol=socket --socket="$SOCKET" -u root -e "FLUSH PRIVILEGES; UPDATE mysql.user SET password=PASSWORD('${ESCAPED}') WHERE user='root' AND host='localhost'; FLUSH PRIVILEGES;" >/dev/null 2>&1; then
    ok "UPDATE (password) succeeded in skip-grant mode."
    return 0
  fi
  return 1
}

# -------------------- MAIN --------------------
require_root
SOCKET="$(get_socket)"

echo
info "This script will set MySQL/MariaDB root password to: ${NEWPASS}"
ok "Socket path: $SOCKET"
echo

command -v mysql >/dev/null 2>&1 || die "mysql client not found. Install mysql-client/mariadb-client."

# Try with Debian maintenance account first (cleanest)
if [[ -f "$DEBIAN_CNF" ]]; then
  info "Trying with Debian maintenance account ($DEBIAN_CNF) ..."
  service_start
  if test_maint_login; then
    ok "Maintenance login OK."
    if set_root_password_multi; then
      ok "Root password set via maintenance account."
      echo
      ok "DONE. Root password is now: ${NEWPASS}"
      info "Test with: mysql -u root -p"
      exit 0
    else
      warn "Could not set password via maintenance account; will use skip-grant-tables."
      FALLBACK=1
    fi
  else
    warn "Cannot login with maintenance account; will use skip-grant-tables."
    FALLBACK=1
  fi
else
  warn "$DEBIAN_CNF not found; will use skip-grant-tables."
  FALLBACK=1
fi

# Fallback: skip-grant-tables
if [[ "${FALLBACK:-0}" -eq 1 ]]; then
  info "Stopping service..."
  service_stop
  info "Starting temporary server with --skip-grant-tables ..."
  if ! start_skip_grants; then
    die "Failed to start mysqld_safe in skip-grant mode. See /tmp/mysqld_safe.log"
  fi

  info "Setting root password in skip-grant mode..."
  if ! set_root_password_skip_grants; then
    stop_skip_grants
    die "Failed to set password in skip-grant mode. Check /tmp/mysqld_safe.log"
  fi

  info "Stopping temporary server and starting normal service..."
  stop_skip_grants
  service_start

  echo
  ok "DONE. Root password is now: ${NEWPASS}"
  info "Test with: mysql -u root -p"
fi
