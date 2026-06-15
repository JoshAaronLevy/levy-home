#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/apps/api/.env}"
LOG_DIR="$ROOT_DIR/build/phase7"
LOG_FILE="$LOG_DIR/home-assistant-activity-api.log"
EVENT_WAIT_SECONDS="${PHASE7_EVENT_WAIT_SECONDS:-120}"
LISTENER_WAIT_SECONDS="${PHASE7_LISTENER_WAIT_SECONDS:-45}"
DRY_RUN="${PHASE7_DRY_RUN:-false}"
SKIP_HA_PREFLIGHT="${PHASE7_SKIP_HA_PREFLIGHT:-false}"

cd "$ROOT_DIR"

read_env_value() {
  local key="$1"

  ENV_FILE="$ENV_FILE" ENV_KEY="$key" node --input-type=module - <<'NODE'
import { config as loadEnv } from 'dotenv';

loadEnv({ path: process.env.ENV_FILE });
console.log(process.env[process.env.ENV_KEY] ?? '');
NODE
}

PORT="$(read_env_value PORT)"
PORT="${PORT:-4000}"
API_BASE_URL="http://localhost:$PORT"
SIMULATOR_API_BASE_URL="${SIMULATOR_API_BASE_URL:-$API_BASE_URL}"
API_PID=""

cleanup() {
  if [[ -n "$API_PID" ]] && kill -0 "$API_PID" 2>/dev/null; then
    echo "==> Stopping API process $API_PID"
    kill "$API_PID" 2>/dev/null || true
    wait "$API_PID" 2>/dev/null || true
  fi
}

trap cleanup EXIT

echo "==> Phase 7 Home Assistant activity simulator verification"
echo "==> Env file: $ENV_FILE"
echo "==> Local API URL: $API_BASE_URL"
echo "==> Simulator API URL: $SIMULATOR_API_BASE_URL"

ENV_FILE="$ENV_FILE" SKIP_HA_PREFLIGHT="$SKIP_HA_PREFLIGHT" node --input-type=module - <<'NODE'
import { config as loadEnv } from 'dotenv';

loadEnv({ path: process.env.ENV_FILE });

const requiredKeys = [
  'HOME_ASSISTANT_MODE',
  'HOME_ASSISTANT_BASE_URL',
  'HOME_ASSISTANT_TOKEN',
  'LEVY_HOME_HA_WEBHOOK_SECRET',
];
const missingKeys = requiredKeys.filter((key) => !process.env[key]?.trim());
const hasTrackedPhones =
  Boolean(process.env.HOME_ASSISTANT_PHONE_ENTITIES?.trim()) ||
  Boolean(process.env.HOME_ASSISTANT_PHONE_ENTITY_PATTERNS?.trim());

if (process.env.HOME_ASSISTANT_MODE !== 'live') {
  missingKeys.push('HOME_ASSISTANT_MODE=live');
}

if (!hasTrackedPhones) {
  missingKeys.push('HOME_ASSISTANT_PHONE_ENTITIES or HOME_ASSISTANT_PHONE_ENTITY_PATTERNS');
}

if (missingKeys.length > 0) {
  console.error('Missing Phase 7 live activity configuration:');
  for (const key of missingKeys) {
    console.error(`  - ${key}`);
  }
  console.error('');
  console.error('Run the discovery helper first, choose exact phone entities or explicit patterns, then set them in apps/api/.env or the shell.');
  process.exit(1);
}

if (process.env.SKIP_HA_PREFLIGHT === 'true' || process.env.SKIP_HA_PREFLIGHT === '1') {
  console.log('==> Home Assistant REST preflight skipped by PHASE7_SKIP_HA_PREFLIGHT');
  process.exit(0);
}

const baseURL = process.env.HOME_ASSISTANT_BASE_URL;
const token = process.env.HOME_ASSISTANT_TOKEN;

try {
  const response = await fetch(new URL('/api/states', baseURL), {
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: 'application/json',
    },
  });

  if (!response.ok) {
    console.error(`Home Assistant REST preflight failed with HTTP ${response.status}.`);
    process.exit(1);
  }

  const states = await response.json();
  const stateCount = Array.isArray(states) ? states.length : 0;
  console.log(`==> Home Assistant REST preflight OK (${stateCount} states visible)`);
} catch (error) {
  console.error(`Home Assistant REST preflight failed: ${error instanceof Error ? error.message : 'unknown error'}`);
  process.exit(1);
}
NODE

if [[ "$DRY_RUN" == "true" || "$DRY_RUN" == "1" ]]; then
  echo "==> Dry run complete. Set PHASE7_DRY_RUN=false to start the API, wait for phone activity, and launch the simulator."
  exit 0
fi

if curl -fsS "$API_BASE_URL/health" >/dev/null 2>&1; then
  echo "A server is already responding at $API_BASE_URL." >&2
  echo "Stop it first so this script can start a known Phase 7 API process with activity enabled." >&2
  exit 1
fi

mkdir -p "$LOG_DIR"
rm -f "$LOG_FILE"

echo "==> Building API"
npm run api:build

echo "==> Starting API with Home Assistant activity enabled"
HOME_ASSISTANT_ACTIVITY_ENABLED=true npm run api:start >"$LOG_FILE" 2>&1 &
API_PID="$!"

echo "==> Waiting for API health"
for _ in $(seq 1 45); do
  if curl -fsS "$API_BASE_URL/health" >/dev/null 2>&1; then
    echo "==> API is healthy"
    break
  fi

  sleep 1
done

if ! curl -fsS "$API_BASE_URL/health" >/dev/null 2>&1; then
  echo "API did not become healthy. Recent API log:" >&2
  tail -n 80 "$LOG_FILE" >&2 || true
  exit 1
fi

wait_for_log() {
  local description="$1"
  local pattern="$2"

  echo "==> Waiting for listener log: $description"
  for _ in $(seq 1 "$LISTENER_WAIT_SECONDS"); do
    if grep -F "$pattern" "$LOG_FILE" >/dev/null 2>&1; then
      echo "==> Confirmed: $description"
      return 0
    fi

    sleep 1
  done

  echo "Timed out waiting for listener log: $description" >&2
  tail -n 120 "$LOG_FILE" >&2 || true
  return 1
}

wait_for_log "authenticated" "Home Assistant activity listener authenticated."
wait_for_log "subscribed to state_changed" "Home Assistant activity listener subscribed to state_changed events."

echo "==> Waiting up to ${EVENT_WAIT_SECONDS}s for phone activity in /api/events"
for _ in $(seq 1 "$EVENT_WAIT_SECONDS"); do
  if API_BASE_URL="$API_BASE_URL" node --input-type=module - <<'NODE'
const response = await fetch(`${process.env.API_BASE_URL}/api/events?limit=500`);
if (!response.ok) {
  process.exit(1);
}

const body = await response.json();
const events = Array.isArray(body.events) ? body.events : [];
const phoneEvents = events.filter((event) => event?.type === 'phone_state_changed');

if (phoneEvents.length === 0) {
  process.exit(1);
}

console.log(`phone_event_count=${phoneEvents.length}`);
NODE
  then
    echo "==> Phone activity is present in /api/events"
    break
  fi

  sleep 1
done

if ! API_BASE_URL="$API_BASE_URL" node --input-type=module - <<'NODE'
const response = await fetch(`${process.env.API_BASE_URL}/api/events?limit=500`);
if (!response.ok) {
  process.exit(1);
}

const body = await response.json();
const events = Array.isArray(body.events) ? body.events : [];
process.exit(events.some((event) => event?.type === 'phone_state_changed') ? 0 : 1);
NODE
then
  echo "No phone activity appeared in /api/events during the wait window." >&2
  echo "Trigger or wait for a tracked iPhone entity to change, then rerun this script or increase PHASE7_EVENT_WAIT_SECONDS." >&2
  exit 1
fi

echo "==> Building, installing, and launching the simulator app against $SIMULATOR_API_BASE_URL"
LEVY_HOME_API_BASE_URL="$SIMULATOR_API_BASE_URL" LAUNCH_APP=true "$ROOT_DIR/scripts/build-install-simulator.sh"

echo "==> Phase 7 verification complete. Open the Activity tab and confirm phone records render newest first."
