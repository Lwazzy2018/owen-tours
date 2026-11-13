#!/usr/bin/env bash
# Runs the database tests on a throwaway local Postgres database.
# Usage: DB=owen_test ./supabase/tests/run_db_tests.sh   (needs psql + createdb permissions)
set -euo pipefail
cd "$(dirname "$0")/.."
DB="${DB:-owen_test}"
dropdb --if-exists "$DB" >/dev/null 2>&1 || true
createdb "$DB"
for f in tests/00_local_supabase_stub.sql migrations/*.sql seed.sql; do
  psql -q -v ON_ERROR_STOP=1 -d "$DB" -f "$f" >/dev/null 2>&1 || { echo "FAILED applying $f"; psql -v ON_ERROR_STOP=1 -d "$DB" -f "$f"; exit 1; }
done
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f tests/01_rls_tests.sql | grep -E "PASSED|FAIL" 
bash tests/02_concurrent_booking_test.sh "$DB"
