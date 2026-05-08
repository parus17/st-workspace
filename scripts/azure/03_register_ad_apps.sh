#!/usr/bin/env bash
# Registers two Azure AD app registrations for the BFF OAuth2 security pattern:
#
#   1. Backend API app  (st-gateway-api)
#      Exposes delegated scopes (read, admin) and defines app roles
#      (Admin, ReadOnly).  backend-01 and gateway validate JWTs against this.
#
#   2. BFF Gateway app  (st-bff-gateway)
#      Confidential OAuth2 client (Web type, with client secret).
#      Handles the auth-code exchange server-side; forwards Bearer tokens to
#      backend-01.  Granted delegated access to the backend API scopes.
#
# Idempotent: re-running updates existing registrations; scope and role GUIDs
# are derived deterministically from their names so they are stable across runs.
#
# After a successful run the four env vars required by scripts/run-local.sh
# are written to  workspace/scripts/.env.local  (gitignored).
#
# Usage:
#   az login
#   ./03_register_ad_apps.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Configurable names ─────────────────────────────────────────────────────────
BACKEND_APP_NAME="st-gateway-api"
BFF_APP_NAME="st-bff-gateway"
SECRET_DISPLAY_NAME="ci-secret"

# Redirect URIs registered on the BFF gateway app.
# Extend this list when adding environments.
REDIRECT_URIS=(
    "http://localhost:8080/login/oauth2/code/azure"
    "https://gateway.braveground-e6fcabac.westeurope.azurecontainerapps.io/login/oauth2/code/azure"
)

# ── [1/7] Resolve account ──────────────────────────────────────────────────────
echo "==> [1/7] Resolve Azure account"
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "    Tenant: $TENANT_ID"

# ── [2/7] Backend API app — create or find ────────────────────────────────────
echo "==> [2/7] Backend API app: $BACKEND_APP_NAME"
BACKEND_CLIENT_ID=$(az ad app list \
    --display-name "$BACKEND_APP_NAME" \
    --query "[0].appId" -o tsv 2>/dev/null || true)

if [[ -z "$BACKEND_CLIENT_ID" ]]; then
    BACKEND_CLIENT_ID=$(az ad app create \
        --display-name "$BACKEND_APP_NAME" \
        --sign-in-audience "AzureADandPersonalMicrosoftAccount" \
        --query appId -o tsv)
    echo "    Created: $BACKEND_CLIENT_ID"
else
    echo "    Exists:  $BACKEND_CLIENT_ID"
fi

if ! az ad sp show --id "$BACKEND_CLIENT_ID" &>/dev/null; then
    az ad sp create --id "$BACKEND_CLIENT_ID" > /dev/null
fi

BACKEND_OBJ_ID=$(az ad app show --id "$BACKEND_CLIENT_ID" --query id -o tsv)

# Access token version 2 is required for AzureADandPersonalMicrosoftAccount audience.
# Must be set before the signInAudience update or the CLI call will fail.
az rest --method PATCH \
    --url "https://graph.microsoft.com/v1.0/applications/$BACKEND_OBJ_ID" \
    --headers "Content-Type=application/json" \
    --body '{"api":{"requestedAccessTokenVersion":2}}'

# ── [3/7] Backend API: App ID URI, scopes, roles ──────────────────────────────
echo "==> [3/7] Backend API: App ID URI + scopes + roles"

az ad app update \
    --id "$BACKEND_CLIENT_ID" \
    --identifier-uris "api://$BACKEND_CLIENT_ID"

# Deterministic UUIDs — derived from project-qualified names so they are stable
# across re-runs even if the app is deleted and re-created.
det_uuid() { python3 -c "import uuid; print(uuid.uuid5(uuid.NAMESPACE_DNS, '$1'))"; }

S_READ_ID=$(det_uuid  "be.parus17.$BACKEND_APP_NAME.scope.read")
S_ADMIN_ID=$(det_uuid "be.parus17.$BACKEND_APP_NAME.scope.admin")
R_ADMIN_ID=$(det_uuid "be.parus17.$BACKEND_APP_NAME.role.Admin.All")
R_RO_ID=$(det_uuid    "be.parus17.$BACKEND_APP_NAME.role.Read.All")

# Scopes — patched via Graph API to avoid shell-quoting issues with --set
SCOPES_JSON=$(printf \
    '[{"adminConsentDescription":"Read access","adminConsentDisplayName":"Read","id":"%s","isEnabled":true,"type":"User","userConsentDescription":"Read access","userConsentDisplayName":"Read","value":"read"},{"adminConsentDescription":"Admin access","adminConsentDisplayName":"Admin","id":"%s","isEnabled":true,"type":"Admin","userConsentDescription":"Admin access","userConsentDisplayName":"Admin","value":"admin"}]' \
    "$S_READ_ID" "$S_ADMIN_ID")

az rest --method PATCH \
    --url "https://graph.microsoft.com/v1.0/applications/$BACKEND_OBJ_ID" \
    --headers "Content-Type=application/json" \
    --body "{\"api\":{\"oauth2PermissionScopes\":$SCOPES_JSON}}"

echo "    Scopes: read, admin"

# App roles — supported directly by az ad app update
ROLES_JSON=$(printf \
    '[{"allowedMemberTypes":["User"],"description":"Full administrative access","displayName":"Admin","id":"%s","isEnabled":true,"value":"Admin.All"},{"allowedMemberTypes":["User"],"description":"Read-only access","displayName":"ReadOnly","id":"%s","isEnabled":true,"value":"Read.All"}]' \
    "$R_ADMIN_ID" "$R_RO_ID")

az ad app update \
    --id "$BACKEND_CLIENT_ID" \
    --app-roles "$ROLES_JSON"

echo "    App roles: Admin, ReadOnly"

# ── [4/7] BFF Gateway app — create or find ───────────────────────────────────
echo "==> [4/7] BFF Gateway app: $BFF_APP_NAME"
BFF_CLIENT_ID=$(az ad app list \
    --display-name "$BFF_APP_NAME" \
    --query "[0].appId" -o tsv 2>/dev/null || true)

if [[ -z "$BFF_CLIENT_ID" ]]; then
    BFF_CLIENT_ID=$(az ad app create \
        --display-name "$BFF_APP_NAME" \
        --sign-in-audience "AzureADandPersonalMicrosoftAccount" \
        --web-redirect-uris "${REDIRECT_URIS[@]}" \
        --query appId -o tsv)
    echo "    Created: $BFF_CLIENT_ID"
else
    echo "    Exists:  $BFF_CLIENT_ID"
    az ad app update \
        --id "$BFF_CLIENT_ID" \
        --web-redirect-uris "${REDIRECT_URIS[@]}"
    echo "    Redirect URIs refreshed"
fi

if ! az ad sp show --id "$BFF_CLIENT_ID" &>/dev/null; then
    az ad sp create --id "$BFF_CLIENT_ID" > /dev/null
fi

BFF_OBJ_ID=$(az ad app show --id "$BFF_CLIENT_ID" --query id -o tsv)
az rest --method PATCH \
    --url "https://graph.microsoft.com/v1.0/applications/$BFF_OBJ_ID" \
    --headers "Content-Type=application/json" \
    --body '{"api":{"requestedAccessTokenVersion":2}}'

# ── [5/7] BFF Gateway: client secret ─────────────────────────────────────────
echo "==> [5/7] BFF Gateway: client secret"
EXISTING_SECRET=$(az ad app credential list \
    --id "$BFF_CLIENT_ID" \
    --query "[?displayName=='$SECRET_DISPLAY_NAME'].displayName" \
    -o tsv 2>/dev/null || true)

if [[ -z "$EXISTING_SECRET" ]]; then
    BFF_CLIENT_SECRET=$(az ad app credential reset \
        --id "$BFF_CLIENT_ID" \
        --display-name "$SECRET_DISPLAY_NAME" \
        --query password -o tsv)
    echo "    Secret '$SECRET_DISPLAY_NAME' created"
else
    BFF_CLIENT_SECRET="<rotate with: az ad app credential reset --id $BFF_CLIENT_ID --display-name $SECRET_DISPLAY_NAME>"
    echo "    Secret '$SECRET_DISPLAY_NAME' already exists — skipping"
    echo "    Run the command above to rotate it; update .env.local manually."
fi

# ── [6/7] Permission grant + admin consent ────────────────────────────────────
echo "==> [6/7] Permission grant + admin consent"

RESOURCE_ACCESS_JSON=$(printf \
    '[{"resourceAppId":"%s","resourceAccess":[{"id":"%s","type":"Scope"},{"id":"%s","type":"Scope"}]}]' \
    "$BACKEND_CLIENT_ID" "$S_READ_ID" "$S_ADMIN_ID")

az ad app update \
    --id "$BFF_CLIENT_ID" \
    --required-resource-accesses "$RESOURCE_ACCESS_JSON"

# Retry admin consent — newly created service principals can take a few seconds
# to propagate across Azure AD before consent is accepted.
for attempt in 1 2 3; do
    if az ad app permission admin-consent --id "$BFF_CLIENT_ID" 2>/dev/null; then
        break
    fi
    [[ $attempt -lt 3 ]] && echo "    Consent not ready yet, retrying in 15s..." && sleep 15
done
echo "    Admin consent granted"

# ── [7/7] Write .env.local + summary ─────────────────────────────────────────
echo "==> [7/7] Write .env.local"

ENV_FILE="$SCRIPT_DIR/../../scripts/.env.local"
cat > "$ENV_FILE" <<EOF
AZURE_TENANT_ID=$TENANT_ID
AZURE_CLIENT_ID=$BFF_CLIENT_ID
AZURE_CLIENT_SECRET=$BFF_CLIENT_SECRET
AZURE_BACKEND_CLIENT_ID=$BACKEND_CLIENT_ID
EOF
echo "    Written to $ENV_FILE"

echo ""
echo "════════════════════════════════════════════════════════════"
echo " Azure AD Registration complete"
echo "════════════════════════════════════════════════════════════"
echo " Tenant ID:             $TENANT_ID"
echo " Backend API client ID: $BACKEND_CLIENT_ID"
echo " BFF Gateway client ID: $BFF_CLIENT_ID"
echo ""
echo " Exposed scopes:"
echo "   api://$BACKEND_CLIENT_ID/read"
echo "   api://$BACKEND_CLIENT_ID/admin"
echo ""
echo " Copy these into gateway/application.properties (or set as env vars):"
echo "   AZURE_TENANT_ID=$TENANT_ID"
echo "   AZURE_CLIENT_ID=$BFF_CLIENT_ID"
echo "   AZURE_BACKEND_CLIENT_ID=$BACKEND_CLIENT_ID"
echo "   AZURE_CLIENT_SECRET=<from .env.local>"
echo ""
echo " Start the local stack:"
echo "   cd workspace && ./scripts/run-local.sh"
echo "════════════════════════════════════════════════════════════"
