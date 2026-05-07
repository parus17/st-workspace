# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Monorepo containing two Spring Boot services and a shared workspace hub.

```
SolutionTemplateWorkspace/
├── backend-01/   # Spring Boot 4.0.6 REST API (Java 25)
├── gateway/      # Spring Boot 4.0.6 API gateway (Java 25) — calls backend-01
├── frontend/     # Angular 21 SPA with Tailwind CSS v4
└── workspace/    # Shared Azure scripts and docs hub
```

Each service lives in its own GitHub repository:

| Directory | GitHub repo |
|---|---|
| `backend-01/` | https://github.com/parus17/st-backend-01 |
| `gateway/` | https://github.com/parus17/st-gateway |
| `frontend/` | https://github.com/parus17/st-frontend |
| `workspace/` | https://github.com/parus17/st-workspace |

---

## Architecture

All Java services follow **hexagonal (Ports & Adapters)** architecture. This is a hard convention — apply it to every new class in every service.

Package layout used across all services (example: `be.parus17.gateway`):

```
be.parus17.<service>/
├── <Service>Application.java        ← Spring Boot entry point, stays at root
├── domain/                          ← pure business objects (records, entities)
├── application/
│   ├── port/
│   │   ├── in/                      ← inbound port interfaces (use cases)
│   │   └── out/                     ← outbound port interfaces (clients, repos)
│   └── service/                     ← use case implementations (@Service)
└── adapter/
    ├── in/
    │   └── web/                     ← REST controllers (@RestController)
    └── out/
        ├── http/                    ← HTTP client adapters (RestClient)
        └── persistence/             ← DB adapters (when added)
```

**Placement rules:**
- REST controllers → `adapter.in.web`
- Use case interfaces → `application.port.in`
- Outbound port interfaces → `application.port.out`
- Use case implementations → `application.service`
- HTTP client adapters + their `@Configuration` → `adapter.out.http`
- Domain records/entities → `domain`

---

## Backend (`backend-01/`)

**Stack:** Spring Boot 4.0.6, Java 25, Maven, Lombok  
**Package:** `be.parus17.backend01`  
**Entry point:** `Backend01Application.java`

### Commands

```bash
# Build
./mvnw clean install

# Run (default port 8080)
./mvnw spring-boot:run

# Run on port 8081 for local development alongside the gateway
./mvnw spring-boot:run -Dspring-boot.run.profiles=local

# Test
./mvnw test

# Single test
./mvnw test -Dtest=ClassName#methodName
```

### Dependencies

- `spring-boot-starter-webmvc` — REST endpoints
- `spring-boot-starter-actuator` — health/metrics endpoints
- `lombok` — annotation-based boilerplate reduction

### Notes

- `application-local.properties` sets `server.port=8081` for running alongside the gateway locally.
- No database or security dependencies yet — add as needed.

---

## Gateway (`gateway/`)

**Stack:** Spring Boot 4.0.6, Java 25, Maven, Lombok  
**Package:** `be.parus17.gateway`  
**Entry point:** `GatewayApplication.java`

The gateway exposes `GET /hello`, which calls backend-01's `GET /hello` and enriches the response.

Response shape:

```json
{
  "message": "Hello from gateway",
  "backendMessage": "<string from backend-01>",
  "backendTimestamp": [year, month, day, hour, minute, second, nano]
}
```

`backendTimestamp` is a `LocalDateTime` serialised by Jackson as a number array (default Spring Boot behaviour — no `write-dates-as-timestamps=false` configured).

### Commands

```bash
# Build
./mvnw clean install

# Run (port 8080)
./mvnw spring-boot:run

# Test
./mvnw test

# Single test
./mvnw test -Dtest=ClassName#methodName
```

### Dependencies

- `spring-boot-starter-webmvc` — REST endpoints and `RestClient` for outbound HTTP
- `spring-boot-starter-actuator` — health/metrics endpoints
- `lombok` — annotation-based boilerplate reduction

### Configuration

| Property | Env var | Default | Purpose |
|---|---|---|---|
| `backend01.base-url` | `BACKEND01_BASE_URL` | `http://localhost:8081` | URL of backend-01 |
| `cors.allowed-origins` | `CORS_ALLOWED_ORIGINS` | `http://localhost:4200` | Comma-separated CORS origins |

Spring Boot's relaxed binding maps env vars to properties automatically (e.g. `BACKEND01_BASE_URL` → `backend01.base-url`).

### Spring profiles

| Profile | Activated by | Effect |
|---|---|---|
| _(default)_ | local run | routes at `/hello`, CORS allows `localhost:4200` |
| `cloud` | `SPRING_PROFILES_ACTIVE=cloud` (set by `03_configure_env.sh`) | `spring.mvc.servlet.path=/api` — every controller route is served under `/api/*`, required for SWA linked backend |

---

## Frontend (`frontend/`)

**Stack:** Angular 21, TypeScript, Tailwind CSS v4, Vite (via `@angular/build:application`)  
**Package manager:** npm

### Commands

```bash
# Install dependencies
npm install

# Serve (dev server, port 4200)
npm start

# Build
npm run build

# Test
npm test
```

### Routing

| Path | Behaviour |
|---|---|
| `/` | Redirects to `/hello` |
| `/hello` | Renders `HelloComponent` |

### Key files

| File | Purpose |
|---|---|
| `src/app/hello/hello.ts` | `HelloComponent` — fetches gateway response via `toSignal`, renders message / backendMessage / backendTimestamp |
| `src/app/hello/hello.service.ts` | `HelloService` — `getHello(): Observable<HelloResponse>` using `HttpClient` |
| `src/app/hello/hello-response.ts` | `HelloResponse` interface — mirrors the gateway JSON shape |
| `src/environments/environment.ts` | Dev config: `apiBaseUrl = 'http://localhost:8080'` |
| `src/environments/environment.prod.ts` | Prod config: `apiBaseUrl = '/api'` (relative — routed by SWA linked backend) |
| `public/staticwebapp.config.json` | SWA navigation fallback; excludes `/api/*` so those requests reach the linked backend |

The production build (default) replaces `environment.ts` with `environment.prod.ts` via `angular.json` `fileReplacements`.

### Tailwind CSS

Tailwind v4 is configured via PostCSS (`postcss.config.json`). The single entry point is `src/styles.css`:

```css
@import "tailwindcss";
```

No `tailwind.config.js` is needed. Custom theme tokens go in `src/styles.css` using `@theme`:

```css
@theme {
  --color-brand: #6366f1;
}
```

### Deployment

Deployed to **Azure Static Web Apps** via GitHub Actions on every push to `main`. The workflow (`deploy.yml`) builds the app with Node 22 and deploys the pre-built `dist/frontend/browser/` output.

**Required GitHub Actions secret:**

| Secret | How to obtain |
|---|---|
| `AZURE_STATIC_WEB_APPS_API_TOKEN` | Output of `scripts/azure/02_setup_github_token.sh` |

**Setup (run once):**

```bash
cd frontend/scripts/azure
az login
./01_setup_infra.sh         # create resource group + Static Web App (Free SKU)
./02_setup_github_token.sh  # push deployment token to GitHub secret
./03_link_backend.sh        # upgrade to Standard SKU, link gateway, set CORS on gateway
```

`03_link_backend.sh` must run after the gateway has been deployed and `gateway/scripts/azure/03_configure_env.sh` has been run.

---

## Local development

```bash
# terminal 1 — backend-01 on port 8081
cd backend-01
./mvnw spring-boot:run -Dspring-boot.run.profiles=local

# terminal 2 — gateway on port 8080 (calls backend-01 on 8081)
cd gateway
./mvnw spring-boot:run

# terminal 3 — frontend dev server on port 4200
cd frontend
npm start
```

Full local flow:

```
Browser :4200/hello  →  HelloService (http://localhost:8080/hello)
                     →  gateway :8080/hello
                     →  backend-01 :8081/hello
```

Test the gateway directly:

```bash
curl http://localhost:8080/hello
```

Open the UI at `http://localhost:4200/hello`.

---

## Workspace (`workspace/`)

Shared scripts and documentation hub. Not a running service.

```
workspace/
├── README.md                    ← hub README with links to all service repos
└── scripts/azure/
    ├── shared_variables.sh      ← shared Azure config (LOCATION, RESOURCE_GROUP, ACR_NAME, …)
    ├── 01_setup_infra.sh        ← shared infra logic (called by service wrappers)
    └── 02_setup_github_oidc.sh  ← shared OIDC logic (called by service wrappers)
```

Each service repo has thin wrapper scripts under `scripts/azure/` that export their own variables and `exec` the shared scripts. To change a shared setting (region, resource group, ACR name, etc.), edit `workspace/scripts/azure/shared_variables.sh` only.

---

## CI/CD

Both services deploy automatically to **Azure Container Apps** on every push to `main`.

```
GitHub (push to main)
  └── GitHub Actions (.github/workflows/deploy.yml)
        ├── OIDC login (no long-lived secrets)
        ├── az acr build  →  Azure Container Registry (acrsolntemplate)
        └── az containerapp update  →  Container App
```

**Required GitHub Actions secrets** (per repo):

| Secret | How to obtain |
|---|---|
| `AZURE_CLIENT_ID` | Output of `02_setup_github_oidc.sh` |
| `AZURE_TENANT_ID` | `az account show --query tenantId -o tsv` |
| `AZURE_SUBSCRIPTION_ID` | `az account show --query id -o tsv` |

**Required GitHub Actions variables** (per repo):

| Variable | Value |
|---|---|
| `AZURE_CONTAINER_REGISTRY` | `acrsolntemplate` |
| `AZURE_CONTAINER_APP_NAME` | `backend-01` or `gateway` |

---

## Azure deployment

### Shared infrastructure

All services share these Azure resources (idempotent to provision multiple times):

| Resource | Name |
|---|---|
| Resource group | `rg_solution_template` |
| Container Registry | `acrsolntemplate` |
| Log Analytics workspace | `log-solution-template` |
| Container Apps environment | `cae-solution-template` |

### Setup (run once per service)

```bash
cd <service>/scripts/azure
az login

./01_setup_infra.sh          # provision shared infra + service Container App
./02_setup_github_oidc.sh    # create App Registration + OIDC federated credential
```

Post-deployment wiring (run after all services are deployed):

```bash
# 1. Wire backend-01 URL into gateway + activate cloud Spring profile
cd gateway/scripts/azure
./03_configure_env.sh

# 2. Link gateway to SWA + set CORS on gateway (requires Standard SKU — script upgrades automatically)
cd frontend/scripts/azure
./03_link_backend.sh
```

### SWA linked backend

In production the frontend never calls the gateway URL directly. Instead:

```
Browser → SWA /api/hello → gateway Container App /api/hello
                            (spring.mvc.servlet.path=/api via cloud profile)
```

`03_link_backend.sh` performs four steps:
1. Upgrades the SWA from Free to Standard SKU (required for linked backend)
2. Retrieves the gateway Container App resource ID
3. Calls `az staticwebapp backends link`
4. Reads the SWA hostname and sets `CORS_ALLOWED_ORIGINS` on the gateway Container App

### Deployed URLs

| Service | URL |
|---|---|
| frontend | `https://delightful-moss-0624fd903.7.azurestaticapps.net` |
| gateway | `https://gateway.braveground-e6fcabac.westeurope.azurecontainerapps.io` |
| backend-01 | `https://backend-01.braveground-e6fcabac.westeurope.azurecontainerapps.io` |

The `/hello` feature is accessible at:  
**`https://delightful-moss-0624fd903.7.azurestaticapps.net/hello`**

### Get a service URL

```bash
# Container App (gateway, backend-01)
az containerapp show \
  --name <container-app-name> \
  --resource-group rg_solution_template \
  --query properties.configuration.ingress.fqdn -o tsv

# Static Web App (frontend)
az staticwebapp show \
  --name swa-soln-template-frontend \
  --resource-group rg_solution_template \
  --query defaultHostname -o tsv
```
