#!/usr/bin/env bash
# Refreshes the mirrored LA County MEHKO register.
#
# The county publishes the permitted list as JSON, updated daily. This fetches
# it and hands it to refresh_permit_registry() unchanged — the RPC does the
# diffing, and demotes any cook whose permit has left the register.
#
# Needs a SERVICE ROLE key: the RPC is revoked from anon and authenticated on
# purpose, because anything that can write the register can mint badges.
#
#   SUPABASE_URL=https://<ref>.supabase.co \
#   SUPABASE_SERVICE_ROLE_KEY=... \
#   ./scripts/refresh_permit_registry.sh
#
# Productionising this means running it on a schedule. pg_cron + pg_net can do
# it inside Postgres with no external runner; a daily CI job also works. Either
# way it must run, or "verified" slowly comes to mean "was verified once".
set -euo pipefail

SOURCE="http://publichealth.lacounty.gov/eh/data/mehko.json"
: "${SUPABASE_URL:?set SUPABASE_URL}"
: "${SUPABASE_SERVICE_ROLE_KEY:?set SUPABASE_SERVICE_ROLE_KEY}"

payload=$(curl -sSL --max-time 60 "$SOURCE")
count=$(printf '%s' "$payload" | python3 -c 'import sys,json; print(len(json.load(sys.stdin).get("programs",[])))')
echo "fetched $count records from the county register"

printf '%s' "$payload" \
  | python3 -c 'import sys,json; print(json.dumps({"p_payload": json.load(sys.stdin)}))' \
  | curl -sS -X POST "$SUPABASE_URL/rest/v1/rpc/refresh_permit_registry" \
      -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
      -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
      -H "Content-Type: application/json" \
      --data-binary @-
echo
