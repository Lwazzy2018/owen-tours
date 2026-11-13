#!/usr/bin/env bash
# Two people booking the last seat at the same moment: 40 parallel sessions each
# try to reserve 1 seat on a 14-seat departure. Exactly 14 must succeed.
set -euo pipefail
DB="${1:-owen_test}"
DEP="22222222-0000-4000-8000-000000000005"
psql -q -d "$DB" -c "update public.departures set seats_booked = 0 where id = '$DEP'" >/dev/null
seq 1 40 | xargs -P 40 -I{} psql -qtA -d "$DB" -c "select public.reserve_seats('$DEP', 1)" > /tmp/owen_concurrency.txt
WINS=$(grep -c '^t$' /tmp/owen_concurrency.txt || true)
BOOKED=$(psql -qtA -d "$DB" -c "select seats_booked from public.departures where id = '$DEP'")
psql -q -d "$DB" -c "update public.departures set seats_booked = 0 where id = '$DEP'" >/dev/null
if [[ "$WINS" == "14" && "$BOOKED" == "14" ]]; then
  echo "CONCURRENCY TEST PASSED: 40 people tried, 14 got seats, 0 overbooked"
else
  echo "CONCURRENCY TEST FAILED: wins=$WINS seats_booked=$BOOKED (expected 14)"; exit 1
fi
