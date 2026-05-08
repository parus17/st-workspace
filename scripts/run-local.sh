#!/usr/bin/env bash
# Starts backend-01 (port 8081) and gateway (port 8080) locally with Azure AD OAuth2.
#
# Setup:
#   cp scripts/.env.local.example scripts/.env.local
#   # fill in your Azure AD values in .env.local
#   ./scripts/run-local.sh
#
# .env.local is gitignored — never commit it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

ENV_FILE="$SCRIPT_DIR/.env.local"
if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
fi

required_vars=(AZURE_TENANT_ID AZURE_CLIENT_ID AZURE_CLIENT_SECRET AZURE_BACKEND_CLIENT_ID)
missing=()
for var in "${required_vars[@]}"; do
    [[ -z "${!var:-}" ]] && missing+=("$var")
done
if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Error: the following env vars are not set: ${missing[*]}"
    echo "Create $ENV_FILE (see .env.local.example) or export them before running."
    exit 1
fi

export AZURE_TENANT_ID AZURE_CLIENT_ID AZURE_CLIENT_SECRET AZURE_BACKEND_CLIENT_ID

cleanup() {
    echo ""
    echo "Stopping services..."
    kill "$BACKEND_PID" "$GATEWAY_PID" 2>/dev/null || true
    wait "$BACKEND_PID" "$GATEWAY_PID" 2>/dev/null || true
    echo "Done."
}
trap cleanup INT TERM EXIT

echo "Starting backend-01 on :8081..."
cd "$ROOT/backend-01"
./mvnw spring-boot:run -Dspring-boot.run.profiles=local \
    > "$SCRIPT_DIR/backend-01.log" 2>&1 &
BACKEND_PID=$!

echo "Starting gateway on :8080..."
cd "$ROOT/gateway"
./mvnw spring-boot:run \
    > "$SCRIPT_DIR/gateway.log" 2>&1 &
GATEWAY_PID=$!

echo ""
echo "Both services starting (output → scripts/backend-01.log and scripts/gateway.log)."
echo "Press Ctrl+C to stop."
echo ""

wait "$BACKEND_PID" "$GATEWAY_PID"
