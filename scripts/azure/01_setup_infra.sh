#!/usr/bin/env bash
# Shared infrastructure setup — invoke via a service wrapper that exports all variables.
# Creates: resource group, ACR, Log Analytics workspace,
#          Container Apps environment, and Container App.
# Run once before the first deployment.
# Shared resources (resource group, ACR, log analytics, environment) are
# idempotent — safe to run even if already provisioned by another service.
set -euo pipefail

: "${RESOURCE_GROUP:?}" "${LOCATION:?}" "${ACR_NAME:?}" \
  "${LOG_ANALYTICS_WS:?}" "${CONTAINER_APP_ENV:?}" "${CONTAINER_APP_NAME:?}"

echo "==> [1/8] Register required resource providers"
az provider register -n Microsoft.App --wait
az provider register -n Microsoft.OperationalInsights --wait

echo "==> [2/8] Resource group"
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION"

echo "==> [3/8] Azure Container Registry (Basic)"
az acr create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$ACR_NAME" \
  --sku Basic \
  --admin-enabled false

echo "==> [4/8] Log Analytics workspace"
az monitor log-analytics workspace create \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-name "$LOG_ANALYTICS_WS" \
  --location "$LOCATION"

LOG_WS_ID=$(az monitor log-analytics workspace show \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-name "$LOG_ANALYTICS_WS" \
  --query customerId -o tsv)

LOG_WS_KEY=$(az monitor log-analytics workspace get-shared-keys \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-name "$LOG_ANALYTICS_WS" \
  --query primarySharedKey -o tsv)

echo "==> [5/8] Container Apps environment"
az containerapp env create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CONTAINER_APP_ENV" \
  --location "$LOCATION" \
  --logs-workspace-id "$LOG_WS_ID" \
  --logs-workspace-key "$LOG_WS_KEY"

echo "==> [6/8] Container App (placeholder image, scales to 0)"
az containerapp create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CONTAINER_APP_NAME" \
  --environment "$CONTAINER_APP_ENV" \
  --image "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest" \
  --target-port 8080 \
  --ingress external \
  --min-replicas 0 \
  --max-replicas 3 \
  --cpu 0.5 \
  --memory 1.0Gi

echo "==> [7/8] System-assigned managed identity on Container App"
PRINCIPAL_ID=$(az containerapp identity assign \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CONTAINER_APP_NAME" \
  --system-assigned \
  --query principalId -o tsv)

echo "==> [8/8] AcrPull role → Container App managed identity"
ACR_ID=$(az acr show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$ACR_NAME" \
  --query id -o tsv)

az role assignment create \
  --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role AcrPull \
  --scope "$ACR_ID"

az containerapp registry set \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CONTAINER_APP_NAME" \
  --server "${ACR_NAME}.azurecr.io" \
  --identity system

echo ""
echo "Infrastructure ready."
echo ""
echo "Set these GitHub Actions variables:"
echo "  AZURE_CONTAINER_REGISTRY = $ACR_NAME"
echo "  AZURE_CONTAINER_APP_NAME = $CONTAINER_APP_NAME"
echo ""
echo "Run 02_setup_github_oidc.sh next to configure authentication."
