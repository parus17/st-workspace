# SolutionTemplateWorkspace

Shared scripts and documentation hub for the solution template monorepo.

```
SolutionTemplateWorkspace/
├── backend-01/          # Spring Boot REST API  →  https://github.com/parus17/st-backend-01
├── gateway/             # Spring Boot API gateway  →  https://github.com/parus17/st-gateway
└── workspace/           # This repo — shared scripts, docs, and frontend (not yet populated)
    └── scripts/azure/   # Shared Azure setup scripts
```

## Services

| Service | Repo | Description |
|---|---|---|
| backend-01 | [parus17/st-backend-01](https://github.com/parus17/st-backend-01) | Spring Boot 4.0.6 REST API |
| gateway | [parus17/st-gateway](https://github.com/parus17/st-gateway) | Spring Boot 4.0.6 API gateway |

---

## Azure setup scripts

Each service repo (`backend-01`, `gateway`) contains thin wrapper scripts under `scripts/azure/` that delegate to the shared implementations here. All shared infrastructure resources (resource group, ACR, Log Analytics workspace, Container Apps environment) are idempotent — running a service's setup when another has already provisioned them is safe.

### Files

| File | Location | Purpose |
|---|---|---|
| `shared_variables.sh` | `workspace/scripts/azure/` | Shared config (sourced, not executed) |
| `01_setup_infra.sh` | `workspace/scripts/azure/` | Shared infra logic |
| `02_setup_github_oidc.sh` | `workspace/scripts/azure/` | Shared OIDC logic |
| `variables.sh` | `<service>/scripts/azure/` | Service-specific config, sources shared vars |
| `01_setup_infra.sh` | `<service>/scripts/azure/` | Wrapper — exports vars, calls shared script |
| `02_setup_github_oidc.sh` | `<service>/scripts/azure/` | Wrapper — exports vars, calls shared script |

To change a value that applies to all services (region, resource group, ACR name, etc.), edit `workspace/scripts/azure/shared_variables.sh` only.

### Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) installed and logged in:
  ```bash
  az login
  az account set --subscription <your-subscription-id>
  ```
- Your account needs **Owner** or **Contributor + User Access Administrator** on the subscription (required to create role assignments).

### Running the scripts

Run from each service's directory. Infra first, then OIDC.

**backend-01**

```bash
cd backend-01/scripts/azure
./01_setup_infra.sh        # provision shared infra + backend-01 Container App
./02_setup_github_oidc.sh  # create App Registration and federated credential
```

**gateway**

```bash
cd gateway/scripts/azure
./01_setup_infra.sh        # provision shared infra + gateway Container App
./02_setup_github_oidc.sh  # create App Registration and federated credential
```

> Shared resources (resource group, ACR, Log Analytics, Container Apps environment) are only provisioned once regardless of which service runs first.

---

## GitHub Actions configuration

After running both scripts for a service, configure its GitHub repo with the values printed at the end of each script.

### Secrets

Go to **Settings → Secrets and variables → Actions → Secrets** in the service's GitHub repo:

| Secret | How to obtain |
|---|---|
| `AZURE_CLIENT_ID` | Printed by `02_setup_github_oidc.sh`. Retrieve later: `az ad app list --display-name sp-github-<repo>-deploy --query '[0].appId' -o tsv` |
| `AZURE_TENANT_ID` | Printed by `02_setup_github_oidc.sh`. Retrieve later: `az account show --query tenantId -o tsv` |
| `AZURE_SUBSCRIPTION_ID` | Printed by `02_setup_github_oidc.sh`. Retrieve later: `az account show --query id -o tsv` |

### Variables

Go to **Settings → Secrets and variables → Actions → Variables** in the service's GitHub repo:

| Variable | Value | Source |
|---|---|---|
| `AZURE_CONTAINER_REGISTRY` | `acrsolntemplate` | `shared_variables.sh` → `ACR_NAME` |
| `AZURE_CONTAINER_APP_NAME` | `backend-01` or `gateway` | `<service>/scripts/azure/variables.sh` → `CONTAINER_APP_NAME` |

---

## Lessons Learned

- **Resource provider registration**: `Microsoft.App` and `Microsoft.OperationalInsights` must be registered in a subscription before Container Apps or Log Analytics can be created. The setup script handles this automatically with `--wait`.
- **OIDC role scope**: Assigning `AcrPush` on the ACR and `Contributor` on the Container App individually was insufficient — `az acr build` also needs ARM-level permissions on the registry resource. Using **`Contributor` at the resource group level** covers all required operations cleanly.
- **ACR name uniqueness**: ACR names are globally unique across all Azure customers. Choose a name specific to your organisation to avoid conflicts.
- **Shared infrastructure**: Resource group, ACR, Log Analytics workspace, and Container Apps environment are shared across services. Setup scripts are idempotent for those resources — running a second service's setup does not break the first.
- **Centralised scripts**: Shared Azure config in a single `shared_variables.sh` prevents config drift between services. Service repos hold thin wrappers that export variables (`set -a`) and `exec` the shared script — no duplication of logic.
- **Subscription diagnostics**: When OIDC login succeeds but subsequent `az` commands fail with permission errors, add `az account show` as an early workflow step to verify which identity and subscription the workflow is operating under.
