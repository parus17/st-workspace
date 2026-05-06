#!/usr/bin/env bash
# Shared OIDC setup — invoke via a service wrapper that exports all variables.
# Creates an App Registration with a federated credential for GitHub Actions
# (OIDC — no long-lived secrets) and grants Contributor on the resource group,
# which covers both az acr build and az containerapp update.
# Run this after 01_setup_infra.sh.
set -euo pipefail

: "${RESOURCE_GROUP:?}" "${GITHUB_ORG:?}" "${GITHUB_REPO:?}" "${GITHUB_BRANCH:?}"

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
APP_DISPLAY_NAME="sp-github-${GITHUB_REPO}-deploy"

echo "==> [1/4] App Registration: $APP_DISPLAY_NAME"
APP_ID=$(az ad app create \
  --display-name "$APP_DISPLAY_NAME" \
  --query appId -o tsv)

echo "==> [2/4] Service principal"
SP_OBJ_ID=$(az ad sp create \
  --id "$APP_ID" \
  --query id -o tsv)

echo "==> [3/4] Federated credential (branch: $GITHUB_BRANCH)"
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters "{
    \"name\": \"github-actions-${GITHUB_BRANCH}\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/${GITHUB_BRANCH}\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"

echo "==> [4/4] Contributor role on resource group $RESOURCE_GROUP"
RG_SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"

az role assignment create \
  --assignee-object-id "$SP_OBJ_ID" \
  --assignee-principal-type ServicePrincipal \
  --role Contributor \
  --scope "$RG_SCOPE"

echo ""
echo "OIDC authentication configured."
echo ""
echo "Add these as GitHub Actions secrets (Settings → Secrets and variables → Actions):"
echo "  AZURE_CLIENT_ID       = $APP_ID"
echo "  AZURE_TENANT_ID       = $TENANT_ID"
echo "  AZURE_SUBSCRIPTION_ID = $SUBSCRIPTION_ID"
