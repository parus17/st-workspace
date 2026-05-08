#!/usr/bin/env bash
# Removes the complete solution deployment:
#
#   1. Entra ID app registrations — BFF OAuth2 apps (st-gateway-api, st-bff-gateway)
#   2. Entra ID app registrations — GitHub OIDC deploy principals (sp-github-*-deploy)
#   3. Azure resource group rg_solution_template and everything inside it:
#        Container Apps (backend-01, gateway)
#        Azure Container Registry (acrsolntemplate)
#        Log Analytics workspace (log-solution-template)
#        Container Apps environment (cae-solution-template)
#        Static Web App (swa-soln-template-frontend)
#        Container App authentication config
#   4. Local .env.local file
#   5. GitHub Actions secrets and variables (requires gh CLI, optional)
#
# Resource group deletion runs asynchronously.  Entra ID objects are deleted
# synchronously so they are gone before you might recreate anything.
#
# Usage:
#   az login
#   ./04_teardown.sh
#
# To also remove GitHub secrets/variables, ensure `gh auth status` passes first.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/shared_variables.sh"

# ── Configurable names ─────────────────────────────────────────────────────────
AD_BACKEND_APP_NAME="st-gateway-api"
AD_BFF_APP_NAME="st-bff-gateway"

# Repos that had OIDC App Registrations created for GitHub Actions CI/CD
OIDC_REPOS=("st-backend-01" "st-gateway" "st-frontend")

# ── Banner ────────────────────────────────────────────────────────────────────
echo "════════════════════════════════════════════════════════════"
echo " Teardown: Solution Template Workspace"
echo "════════════════════════════════════════════════════════════"
echo " Resource group:  $RESOURCE_GROUP  (region: $LOCATION)"
echo " ACR:             $ACR_NAME"
echo " Entra ID apps:   $AD_BACKEND_APP_NAME, $AD_BFF_APP_NAME"
echo " OIDC principals: $(IFS=', '; echo "${OIDC_REPOS[*]/#/sp-github-}" | sed 's/sp-github-/sp-github-/g')"
echo ""
echo " This permanently deletes all Azure resources and Entra ID"
echo " app registrations listed above."
echo ""
read -r -p "Type 'yes' to continue: " CONFIRM
[[ "$CONFIRM" == "yes" ]] || { echo "Aborted."; exit 0; }
echo ""

# ── [1/5] Entra ID: BFF OAuth2 app registrations ─────────────────────────────
echo "==> [1/5] Remove Entra ID OAuth2 app registrations"

for APP_NAME in "$AD_BACKEND_APP_NAME" "$AD_BFF_APP_NAME"; do
    APP_ID=$(az ad app list \
        --display-name "$APP_NAME" \
        --query "[0].appId" -o tsv 2>/dev/null || true)
    if [[ -n "$APP_ID" && "$APP_ID" != "None" ]]; then
        az ad app delete --id "$APP_ID"
        echo "    Deleted: $APP_NAME  ($APP_ID)"
    else
        echo "    Not found (skipped): $APP_NAME"
    fi
done

# ── [2/5] Entra ID: GitHub OIDC deploy principals ────────────────────────────
echo "==> [2/5] Remove GitHub OIDC app registrations"

for REPO in "${OIDC_REPOS[@]}"; do
    APP_NAME="sp-github-${REPO}-deploy"
    APP_ID=$(az ad app list \
        --display-name "$APP_NAME" \
        --query "[0].appId" -o tsv 2>/dev/null || true)
    if [[ -n "$APP_ID" && "$APP_ID" != "None" ]]; then
        az ad app delete --id "$APP_ID"
        echo "    Deleted: $APP_NAME  ($APP_ID)"
    else
        echo "    Not found (skipped): $APP_NAME"
    fi
done

# ── [3/5] Azure resource group ────────────────────────────────────────────────
echo "==> [3/5] Delete resource group: $RESOURCE_GROUP"

if az group exists --name "$RESOURCE_GROUP" -o tsv | grep -q "^true$"; then
    az group delete --name "$RESOURCE_GROUP" --yes --no-wait
    echo "    Deletion initiated (async). Contains: Container Apps, ACR, Log Analytics,"
    echo "    Container App environment, Static Web App."
    echo "    Monitor: az group show --name $RESOURCE_GROUP --query properties.provisioningState -o tsv"
else
    echo "    Not found (skipped): $RESOURCE_GROUP"
fi

# ── [4/5] Local .env.local ────────────────────────────────────────────────────
echo "==> [4/5] Remove local credentials file"

ENV_FILE="$SCRIPT_DIR/../../scripts/.env.local"
if [[ -f "$ENV_FILE" ]]; then
    rm "$ENV_FILE"
    echo "    Deleted: $ENV_FILE"
else
    echo "    Not found (skipped)"
fi

# ── [5/5] GitHub Actions secrets and variables ────────────────────────────────
echo "==> [5/5] Remove GitHub Actions secrets and variables"

if ! command -v gh &>/dev/null; then
    echo "    gh CLI not found — skipping GitHub cleanup."
    echo "    Remove these manually in each repo's Settings > Secrets and variables:"
    for REPO in "${OIDC_REPOS[@]}"; do
        echo "      ${GITHUB_ORG}/${REPO}: AZURE_CLIENT_ID, AZURE_TENANT_ID,"
        echo "        AZURE_SUBSCRIPTION_ID, AZURE_CONTAINER_REGISTRY,"
        echo "        AZURE_CONTAINER_APP_NAME"
    done
    echo "      ${GITHUB_ORG}/st-frontend: AZURE_STATIC_WEB_APPS_API_TOKEN"
elif ! gh auth status &>/dev/null; then
    echo "    gh CLI not authenticated — skipping GitHub cleanup."
    echo "    Run 'gh auth login' then re-run this step manually."
else
    # Container App repos — OIDC secrets + Actions variables
    for REPO in "st-backend-01" "st-gateway"; do
        for SECRET in AZURE_CLIENT_ID AZURE_TENANT_ID AZURE_SUBSCRIPTION_ID; do
            gh secret delete "$SECRET" \
                --repo "${GITHUB_ORG}/${REPO}" 2>/dev/null \
                && echo "    Deleted secret  ${GITHUB_ORG}/${REPO}  $SECRET" \
                || echo "    Not found (skipped): ${GITHUB_ORG}/${REPO}  $SECRET"
        done
        for VAR in AZURE_CONTAINER_REGISTRY AZURE_CONTAINER_APP_NAME; do
            gh variable delete "$VAR" \
                --repo "${GITHUB_ORG}/${REPO}" 2>/dev/null \
                && echo "    Deleted variable ${GITHUB_ORG}/${REPO}  $VAR" \
                || echo "    Not found (skipped): ${GITHUB_ORG}/${REPO}  $VAR"
        done
    done

    # Frontend repo — SWA deployment token
    gh secret delete AZURE_STATIC_WEB_APPS_API_TOKEN \
        --repo "${GITHUB_ORG}/st-frontend" 2>/dev/null \
        && echo "    Deleted secret  ${GITHUB_ORG}/st-frontend  AZURE_STATIC_WEB_APPS_API_TOKEN" \
        || echo "    Not found (skipped): ${GITHUB_ORG}/st-frontend  AZURE_STATIC_WEB_APPS_API_TOKEN"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════"
echo " Teardown complete"
echo "════════════════════════════════════════════════════════════"
echo ""
echo " Entra ID app registrations: deleted synchronously."
echo " Resource group deletion:    running in the background."
echo ""
echo " Wait for resource group to finish:"
echo "   az group show --name $RESOURCE_GROUP -o table 2>/dev/null || echo Deleted"
echo "════════════════════════════════════════════════════════════"
