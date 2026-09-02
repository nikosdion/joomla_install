#!/usr/bin/env bash
# Copyright (c) 2026 Nicholas K. Dionysopoulos
# SPDX-License-Identifier: MIT

# =============================================================================
# install.sh — Install a Joomla site locally
# =============================================================================
# Usage: ./install.sh <site-slug> [joomla-version]
#
# Arguments:
#   site-slug       Mandatory. Alphanumeric + hyphens. Used as the directory
#                   name, database name, and database username.
#   joomla-version  Optional. Examples: latest, 5, 5.2, 5.2.1
#                   Defaults to "latest".
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------------------
# Load .env
# -----------------------------------------------------------------------------
if [[ ! -f "${SCRIPT_DIR}/.env" ]]; then
    echo "ERROR: .env file not found. Copy env.sample to .env and configure it." >&2
    exit 1
fi

# shellcheck disable=SC1091
set -a
source "${SCRIPT_DIR}/.env"
set +a

# -----------------------------------------------------------------------------
# Apply defaults
# -----------------------------------------------------------------------------
SITES_PREFIX="${SITES_PREFIX:-/home/${USER}/Sites}"
DOMAIN_SUFFIX="${DOMAIN_SUFFIX:-local}"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"
DB_ROOT_USER="${DB_ROOT_USER:-root}"
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-}"
ADMIN_FULLNAME="${ADMIN_FULLNAME:-Administrator}"
ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin1234}"
CACHE_DIR="${CACHE_DIR:-${HOME}/.cache/joomla-install}"

# -----------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <site-slug> [joomla-version]" >&2
    echo "  site-slug       e.g. mysite" >&2
    echo "  joomla-version  e.g. latest, 5, 5.2, 5.2.1  (default: latest)" >&2
    exit 1
fi

SITE_SLUG="$1"
VERSION_REQUEST="${2:-latest}"

# Validate site slug (alphanumeric + hyphens only)
if [[ ! "${SITE_SLUG}" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*$ ]]; then
    echo "ERROR: Site slug '${SITE_SLUG}' is invalid. Use only letters, digits, and hyphens." >&2
    exit 1
fi

SITE_DIR="${SITES_PREFIX}/${SITE_SLUG}"
SITE_URL="https://${SITE_SLUG}.${DOMAIN_SUFFIX}"
DB_NAME="${SITE_SLUG}"
DB_USER="${SITE_SLUG}"
DB_PASS="${SITE_SLUG}"

# -----------------------------------------------------------------------------
# Helper: print a section header
# -----------------------------------------------------------------------------
section() {
    echo ""
    echo ">>> $*"
}

# -----------------------------------------------------------------------------
# Dependency checks
# -----------------------------------------------------------------------------
section "Checking dependencies"

for cmd in mysql php curl gunzip; do
    if ! command -v "${cmd}" &>/dev/null; then
        echo "ERROR: Required command '${cmd}' not found in PATH." >&2
        exit 1
    fi
done

PHP_BIN="$(command -v php)"

# Prefer mariadb over mysql when both are available
if command -v mariadb &>/dev/null; then
    MYSQL_BIN="mariadb"
else
    MYSQL_BIN="mysql"
fi

# -----------------------------------------------------------------------------
# Step 1 — Database setup
# -----------------------------------------------------------------------------
section "Setting up database"

MYSQL_OPTS=(
    -h "${DB_HOST}"
    -P "${DB_PORT}"
    -u "${DB_ROOT_USER}"
)
if [[ -n "${DB_ROOT_PASSWORD}" ]]; then
    MYSQL_OPTS+=(-p"${DB_ROOT_PASSWORD}")
fi

run_sql() {
    "${MYSQL_BIN}" "${MYSQL_OPTS[@]}" -e "$1"
}

echo "Dropping existing database/user if present..."
run_sql "DROP DATABASE IF EXISTS \`${DB_NAME}\`;"
run_sql "DROP USER IF EXISTS '${DB_USER}'@'localhost';"
run_sql "DROP USER IF EXISTS '${DB_USER}'@'%';"

echo "Creating database '${DB_NAME}'..."
run_sql "CREATE DATABASE \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

echo "Creating user '${DB_USER}'..."
run_sql "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
run_sql "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';"
run_sql "FLUSH PRIVILEGES;"

echo "Database setup complete."

# -----------------------------------------------------------------------------
# Step 2 — Site directory
# -----------------------------------------------------------------------------
section "Preparing site directory"

if [[ -d "${SITE_DIR}" ]]; then
    echo "Removing existing directory ${SITE_DIR} ..."
    rm -rf "${SITE_DIR}"
fi

mkdir -p "${SITE_DIR}"
echo "Created ${SITE_DIR}"

# -----------------------------------------------------------------------------
# Step 3 — Resolve Joomla version and download URL
# -----------------------------------------------------------------------------
section "Resolving Joomla version"

SOURCES_URL="https://getpanopticon.com/checksums/sources.json.gz"
mkdir -p "${CACHE_DIR}"
SOURCES_CACHE="${CACHE_DIR}/sources.json"
SOURCES_GZ_CACHE="${CACHE_DIR}/sources.json.gz"

# Refresh sources.json if it is older than 1 day
if [[ ! -f "${SOURCES_CACHE}" ]] || \
   [[ $(find "${SOURCES_CACHE}" -mtime +1 -print 2>/dev/null | wc -l) -gt 0 ]]; then
    echo "Downloading sources index..."
    curl -fsSL -o "${SOURCES_GZ_CACHE}" "${SOURCES_URL}"
    gunzip -f "${SOURCES_GZ_CACHE}"
fi

# Delegate version resolution and URL selection to PHP
DOWNLOAD_INFO="$(
    "${PHP_BIN}" "${SCRIPT_DIR}/resolve_version.php" \
        "${SOURCES_CACHE}" \
        "${VERSION_REQUEST}"
)"

if [[ -z "${DOWNLOAD_INFO}" ]]; then
    echo "ERROR: Could not resolve a Joomla version matching '${VERSION_REQUEST}'." >&2
    exit 1
fi

JOOMLA_VERSION="$(echo "${DOWNLOAD_INFO}" | cut -d'|' -f1)"
DOWNLOAD_URL="$(echo "${DOWNLOAD_INFO}" | cut -d'|' -f2)"

echo "Resolved version: ${JOOMLA_VERSION}"
echo "Download URL    : ${DOWNLOAD_URL}"

# -----------------------------------------------------------------------------
# Step 4 — Download (with 90-day cache)
# -----------------------------------------------------------------------------
section "Downloading Joomla ${JOOMLA_VERSION}"

# Derive a cache filename from the URL
URL_HASH="$(echo "${DOWNLOAD_URL}" | md5sum | cut -d' ' -f1)"
EXT="tar.gz"
case "${DOWNLOAD_URL}" in
    *.tar.zst*)  EXT="tar.zst" ;;
    *.tar.bz2*)  EXT="tar.bz2" ;;
    *.tar.gz*)   EXT="tar.gz" ;;
    *.zip*)      EXT="zip" ;;
esac

CACHED_ARCHIVE="${CACHE_DIR}/joomla-${JOOMLA_VERSION}-${URL_HASH}.${EXT}"

if [[ -f "${CACHED_ARCHIVE}" ]] && \
   [[ $(find "${CACHED_ARCHIVE}" -mtime +90 -print 2>/dev/null | wc -l) -eq 0 ]]; then
    echo "Using cached archive: ${CACHED_ARCHIVE}"
else
    echo "Downloading..."
    curl -fSL --progress-bar -o "${CACHED_ARCHIVE}" "${DOWNLOAD_URL}"
fi

# -----------------------------------------------------------------------------
# Step 5 — Extract
# -----------------------------------------------------------------------------
section "Extracting Joomla ${JOOMLA_VERSION} to ${SITE_DIR}"

case "${EXT}" in
    tar.zst)
        if command -v zstd &>/dev/null; then
            zstd -d -c "${CACHED_ARCHIVE}" | tar -xf - -C "${SITE_DIR}"
        else
            echo "ERROR: 'zstd' not found; cannot extract .tar.zst archive." >&2
            exit 1
        fi
        ;;
    tar.bz2)
        tar -xjf "${CACHED_ARCHIVE}" -C "${SITE_DIR}"
        ;;
    tar.gz)
        tar -xzf "${CACHED_ARCHIVE}" -C "${SITE_DIR}"
        ;;
    zip)
        if command -v unzip &>/dev/null; then
            unzip -q "${CACHED_ARCHIVE}" -d "${SITE_DIR}"
        else
            echo "ERROR: 'unzip' not found; cannot extract .zip archive." >&2
            exit 1
        fi
        ;;
    *)
        echo "ERROR: Unknown archive format '${EXT}'." >&2
        exit 1
        ;;
esac

echo "Extraction complete."

# Some Joomla archives wrap everything in a subdirectory — flatten if needed.
SUBDIRS=("${SITE_DIR}"/*)
if [[ ${#SUBDIRS[@]} -eq 1 ]] && [[ -d "${SUBDIRS[0]}" ]]; then
    SUBDIR="${SUBDIRS[0]}"
    echo "Flattening single subdirectory: ${SUBDIR}"
    mv "${SUBDIR}"/* "${SUBDIR}"/.[!.]* "${SITE_DIR}/" 2>/dev/null || true
    rmdir "${SUBDIR}"
fi

# Verify the installer CLI entry point exists
if [[ ! -f "${SITE_DIR}/installation/joomla.php" ]]; then
    echo "ERROR: ${SITE_DIR}/installation/joomla.php not found after extraction." >&2
    exit 1
fi

# Verify the site CLI entry point exists
if [[ ! -f "${SITE_DIR}/cli/joomla.php" ]]; then
    echo "ERROR: ${SITE_DIR}/cli/joomla.php not found after extraction." >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 6 — Install Joomla via CLI
# -----------------------------------------------------------------------------
section "Installing Joomla via CLI"

"${PHP_BIN}" "${SITE_DIR}/installation/joomla.php" install \
    --site-name="${SITE_SLUG}" \
    --admin-user="${ADMIN_FULLNAME}" \
    --admin-username="${ADMIN_USERNAME}" \
    --admin-password="${ADMIN_PASSWORD}" \
    --admin-email="${ADMIN_USERNAME}@example.com" \
    --db-type=mysqli \
    --db-host="${DB_HOST}:${DB_PORT}" \
    --db-user="${DB_USER}" \
    --db-pass="${DB_PASS}" \
    --db-name="${DB_NAME}" \
    --db-prefix="jos_" \
    --db-encryption=0 \
    --public-folder=""

# -----------------------------------------------------------------------------
# Step 7 — Remove installation directory
# -----------------------------------------------------------------------------
section "Removing installation directory"

if [[ -d "${SITE_DIR}/installation" ]]; then
    rm -rf "${SITE_DIR}/installation"
    echo "Removed ${SITE_DIR}/installation"
else
    echo "installation directory not found — skipping."
fi

# -----------------------------------------------------------------------------
# Done — print summary
# -----------------------------------------------------------------------------
echo ""
echo "============================================================"
echo " Joomla ${JOOMLA_VERSION} installed on ${SITE_URL}"
echo "============================================================"
echo ""
echo "Your Super User login information is as follows."
echo ""
echo " URL      : ${SITE_URL}/administrator"
echo " Username : ${ADMIN_USERNAME}"
echo " Password : ${ADMIN_PASSWORD}"
echo ""
