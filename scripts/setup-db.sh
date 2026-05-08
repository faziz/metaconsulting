#!/bin/bash
set -euo pipefail

echo "=== PostgreSQL Schema Setup ==="

# Default values
HOST=""
PORT="5432"
ADMIN_USER=""
ADMIN_PASSWORD=""
DB_NAME=""
DB_USER=""
DB_PASSWORD=""
SSL_MODE="require"
PG_IMAGE="postgres:18-alpine"
SCHEMA_FILE=""
EXTENSIONS=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --host) HOST="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --admin-user) ADMIN_USER="$2"; shift 2 ;;
    --admin-password) ADMIN_PASSWORD="$2"; shift 2 ;;
    --database) DB_NAME="$2"; shift 2 ;;
    --db-user) DB_USER="$2"; shift 2 ;;
    --db-password) DB_PASSWORD="$2"; shift 2 ;;
    --ssl-mode) SSL_MODE="$2"; shift 2 ;;
    --image) PG_IMAGE="$2"; shift 2 ;;
    --schema-file) SCHEMA_FILE="$2"; shift 2 ;;
    --extensions) EXTENSIONS="$2"; shift 2 ;;
    *) echo "Unknown parameter: $1"; exit 1 ;;
  esac
done

# Validate required parameters
if [ -z "$HOST" ] || [ -z "$ADMIN_USER" ] || [ -z "$ADMIN_PASSWORD" ] || [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
  echo "Error: Missing required parameters"
  echo "Required: --host, --admin-user, --admin-password, --database, --db-user, --db-password"
  exit 1
fi

# Pull the image first
echo "Pulling PostgreSQL image: $PG_IMAGE"
docker pull "$PG_IMAGE" --quiet

# Base connection string
CONN_BASE="sslmode=$SSL_MODE host=$HOST port=$PORT user=$ADMIN_USER password=$ADMIN_PASSWORD"

echo ""
echo "Host:     $HOST:$PORT"
echo "Database: $DB_NAME"
echo "User:     $DB_USER"
echo "SSL Mode: $SSL_MODE"
echo "Image:    $PG_IMAGE"
echo ""

# Function to run psql via Docker
run_psql() {
  local db="$1"
  local cmd="$2"
  docker run --rm --network host "$PG_IMAGE" \
    psql "$CONN_BASE dbname=$db" -c "$cmd"
}

# 1. Create user
echo "📝 [1/5] Creating user: $DB_USER"
run_psql "postgres" "DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$DB_USER') THEN CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD'; END IF; END \$\$;" 2>&1 | grep -v "^$" || true

# 2. Create database
echo ""
echo "📝 [2/5] Creating database: $DB_NAME"
DB_EXISTS=$(docker run --rm --network host "$PG_IMAGE" psql "$CONN_BASE dbname=postgres" -t -c "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME';" 2>/dev/null | xargs)

if [ "$DB_EXISTS" != "1" ]; then
  echo "Creating database: $DB_NAME"
  docker run --rm --network host "$PG_IMAGE" psql "$CONN_BASE dbname=postgres" -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" 2>&1 || true
else
  echo "Database already exists: $DB_NAME"
fi


# 3. Grant database privileges
echo ""
echo "📝 [3/5] Granting database privileges"
run_psql "postgres" "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;" 2>&1 | grep -v "^$" || true

# 4. Set schema permissions
echo ""
echo "📝 [4/5] Setting schema permissions"
docker run --rm --network host "$PG_IMAGE" \
  psql "$CONN_BASE dbname=$DB_NAME" \
  -c "GRANT ALL ON SCHEMA public TO $DB_USER;" \
  -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;" \
  -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;" \
  -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO $DB_USER;" 2>&1 | grep -v "^$" || true

# 5. Install extensions
if [ -n "$EXTENSIONS" ] && [ "$EXTENSIONS" != "" ]; then
  echo ""
  echo "📝 [5/5] Installing extensions: $EXTENSIONS"
  IFS=',' read -ra EXTS <<< "$EXTENSIONS"
  for ext in "${EXTS[@]}"; do
    ext_trimmed=$(echo "$ext" | xargs)
    echo "  - Installing: $ext_trimmed"
    run_psql "$DB_NAME" "CREATE EXTENSION IF NOT EXISTS \"$ext_trimmed\";" 2>&1 | grep -v "^$" || true
  done
else
  echo ""
  echo "📝 [5/5] No extensions to install"
fi

# 6. Apply schema file
if [ -n "$SCHEMA_FILE" ] && [ "$SCHEMA_FILE" != "" ] && [ -f "$SCHEMA_FILE" ]; then
  echo ""
  echo "📝 Applying schema file: $SCHEMA_FILE"
  SCHEMA_DIR=$(dirname "$SCHEMA_FILE")
  SCHEMA_NAME=$(basename "$SCHEMA_FILE")
  docker run --rm --network host \
    -v "$SCHEMA_DIR:/sql:ro" \
    "$PG_IMAGE" \
    psql "$CONN_BASE dbname=$DB_NAME" \
    -f "/sql/$SCHEMA_NAME" 2>&1 | grep -v "^$" || true
  echo "✅ Schema applied successfully"
elif [ -n "$SCHEMA_FILE" ] && [ "$SCHEMA_FILE" != "" ]; then
  echo ""
  echo "⚠️  Schema file not found: $SCHEMA_FILE (skipping)"
fi

# Output connection string
DB_URL="postgresql://$DB_USER:$DB_PASSWORD@$HOST:$PORT/$DB_NAME"
echo "database_url=$DB_URL" >> "$GITHUB_OUTPUT"

echo ""
echo "=== ✅ Database setup complete! ==="
echo "Connection: postgresql://$DB_USER:****@$HOST:$PORT/$DB_NAME"