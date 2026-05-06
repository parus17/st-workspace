#!/usr/bin/env bash
# Shared Azure configuration for all services in this workspace.
# Source this file from each service's variables.sh — do not run directly.

LOCATION="westeurope"
RESOURCE_GROUP="rg_solution_template"

# ACR name: globally unique, alphanumeric only (no hyphens or underscores)
ACR_NAME="acrsolntemplate"

LOG_ANALYTICS_WS="log-solution-template"
CONTAINER_APP_ENV="cae-solution-template"

# GitHub organisation and default branch — used to scope OIDC federated credentials
GITHUB_ORG="parus17"
GITHUB_BRANCH="main"
