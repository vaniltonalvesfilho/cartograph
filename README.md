# Cartograph

A distributed task runner with a group/project hierarchy, its own DSL for defining pipelines, cron scheduling, job chaining, and real-time execution tracking.

**You define the map (the DSL) — Cartograph runs the route, step by step.**

## Stack

| Layer | Technology |
|--------|------------|
| Backend | Elixir 1.15 + Phoenix 1.8 + Bandit |
| Queues | Oban 2.18 (PostgreSQL-backed) |
| GraphQL | Absinthe 1.7 + absinthe_phoenix (WebSocket subscriptions) |
| Database | PostgreSQL |
| Frontend | Angular 18 (standalone components) + custom theme (CSS variables, Notion style) |
| GraphQL client | Apollo Angular 7 + graphql-ws |
| Graph | elkjs (ELK layout) |
| Desktop | Electron 33 (`apps/desktop`, wraps the web app) |
| AI | Anthropic Messages API (the `agent` step) |
| Secrets | AES-256-GCM at rest (key derived from `SECRET_KEY_BASE`) |
| Clustering | libcluster 3.3 (configurable via env var) |

## A DSL

```groovy
processFiles {
    step "readDirectory" {
        path "data/inbox"
    },
    step "filter" {
        extension "txt"
    },
    step "transform" {
        operation "uppercase"
    },
    step "writeOutput" {
        path "data/outbox"
    },
}
```

The identifier before `{` is the job name. Each `step "name" { ... }` references an implementation registered in the backend. Supported parameters: strings, numbers, and booleans. The DSL also supports branching with `if/else` over the execution state.

Steps share a **state** map: one step writes a key, later steps read it — including across `use`-chained jobs.

### Available steps

| Step | What it does | Main parameters |
|------|--------------|-----------------|
| `readDirectory` | lists files in a directory of the project sandbox | `path` |
| `filter` | keeps only files with a given extension | `extension` |
| `transform` | transforms file content | `operation` (e.g. `uppercase`) |
| `writeOutput` | writes (or copies, when there was no transform) to the output dir | `path` |
| `parseJson` | reads a JSON file into the state | `path` / `file_key`, `root_path`, `result_key` |
| `parseXml` | reads an XML file into the state | `path` / `file_key`, `root_element`, `result_key` |
| `writeJson` | writes a state key as JSON | `path`, `data_key`, `pretty` |
| `writeXml` | writes a state key as XML | `path`, `data_key`, `root_element`, `row_element` |
| `queryDatabase` | runs a `SELECT` on a data source, rows go to the state | `source`, `query`, `result_key` |
| `executeDatabase` | runs `INSERT`/`UPDATE`/`DELETE`, once per row of a state key | `source`, `query`, `rows_from`, `columns` |
| `validate` | format gate (`email`, `cpf`, `cnpj`, `telefone`, `cep`, `regex`) | one param per validator + `pattern` |
| `agent` | calls a Claude model and writes the answer to the state | `secret`, `prompt`, `model`, `system`, `output`, `maxTokens`, `tools`, `maxIterations` |
| `notify` | posts a message to a project Slack webhook | `secret`, `message` |
| `delay` | sleeps N seconds (honours cancellation) | `seconds` |

File paths are resolved inside the **project's own sandbox** — traversal outside it is rejected.

### Job chaining

A job can chain another one inline, expanding its steps into the same execution:

```groovy
mainPipeline {
    use "data-ingestion-8iqX81Va",
    use "data-transformation-Kp3zQ0Lm",
    step "notify" { secret "slack-uI0IOQ45" },
}
```

Each reference (`use "..."` or `job "..."`) points to the job's global **public code** (`<identifier>-<suffix>`), resolved at runtime with a user access check. Cycles are detected and rejected with an error.

The `notify` step posts a message to a Slack incoming webhook registered on the project (project page → **Slack Webhooks**, Navigator+ only). The webhook gets a public code (`slack-<suffix>`) that the DSL references via `secret`; the URL itself is stored encrypted and never leaves the server.

## Features

- **Hierarchy**: Groups → Subgroups → Projects → Jobs (unlimited depth)
- **Dashboard**: global metrics (running jobs, success rate, scheduled, etc.)
- **Cron**: scheduling via cron expression with a visual helper in the frontend
- **Execution window**: optional `release_at` / `archive_at` per job — outside it the job does not run
- **Execution**: steps run sequentially via Oban workers
- **Execution history**: per-job list with the trigger that started each run (manual or cron)
- **Live logs**: via SSE (REST) and GraphQL subscriptions (WebSocket)
- **Visual pipeline**: GitLab CI-style view on the execution screen
- **Dependency graph**: interactive DAG with elkjs (ELK) layout on the job listing, with live status
- **Visual editor**: low-code canvas to assemble a job as a graph and generate the DSL
- **AI agents**: the `agent` step calls Claude, with per-project credentials and token budget
- **Data sources**: PostgreSQL/MySQL connections registered once and assigned to projects
- **Files area**: browse, upload, download, create folders and delete inside each project's sandbox
- **Email**: configurable SMTP relay, used to notify members when a job fails
- **Slack**: `notify` step posting to incoming webhooks registered per project
- **Monitoring**: `/monitor` with CPU (OS and BEAM), memory, disk and Oban queues
- **Authorization**: access levels (Wayfarer → Cartographer) cascading group → project → job
- **Accounts**: user management, optional TOTP two-factor, and personal API tokens
- **i18n**: interface in Portuguese and English (switch in real time)
- **Dual API**: REST and GraphQL coexist — REST kept for compatibility
- **Desktop app**: Electron client pointing at any Cartograph backend
- **Theme**: light/dark, persisted in localStorage

## Integrations

### Data sources (databases)

An admin registers a connection once (**Administration → Data Sources**): `postgres` or
`mysql`, host/port/database/user, optional SSL, and a **slug** (e.g. `mysql-local`). The
password is encrypted at rest and never returned by the API. Each data source is then
**assigned to the projects** allowed to use it, and the DSL references it by slug:

```groovy
syncCustomers {
    step "queryDatabase" {
        source "postgres-crm",
        query "SELECT id, email FROM customers WHERE active = true",
        result_key "rows"
    },
    step "validate" { email "rows.email" },
    step "executeDatabase" {
        source "mysql-billing",
        query "INSERT INTO contacts (ext_id, email) VALUES (?, ?)",
        rows_from "rows",
        columns "id, email"
    },
}
```

`rows_from` names the state key holding the rows and `columns` (comma-separated) picks
which field of each row feeds each placeholder, in order — the statement runs once per row.

A step whose project has no assignment to that source fails — the slug alone grants nothing.

### AI agent jobs

Register an Anthropic credential on the project (Navigator+); it gets a public code
(`anthropic-<suffix>`) and the API key is stored encrypted, write-only. The `agent` step
interpolates `{{key}}` from the state into the prompt and writes the answer back:

```groovy
reviewReport {
    step "parseJson" { path "data/report.json", result_key "report" },
    step "agent" {
        secret "anthropic-uI0IOQ45",
        model "claude-opus-4-8",
        system "You are a strict reviewer. Answer in English.",
        prompt "Review the following report.\n\n{{report}}",
        output "review",
        maxTokens 2048
    },
    step "notify" { secret "slack-uI0IOQ45", message "Review done" },
}
```

Token usage and estimated cost are recorded per step, and a job can define an
**agent token budget** that caps how much a single execution may consume.

**Tool use.** With a `tools` param the agent stops merely writing text and calls
existing steps, deciding for itself which and in what order:

```groovy
step "agent" {
    secret "anthropic-uI0IOQ45",
    prompt "Find every invoice in the inbox and summarise the totals.",
    tools "readDirectory,filter,parseJson",
    maxIterations 5,
    output "summary"
}
```

Each call runs the real step against the shared state and is recorded as a child
step execution, so the history and the flow graph show what the agent actually
did. Two independent gates gate the reach: a step must declare itself agent-safe
in code, *and* you must name it in `tools` (empty by default, and there is no
`tools "*"`). The current safe set is read-only or pure — `readDirectory`,
`filter`, `transform`, `validate`, `parseJson`, `parseXml`.

Because a tool takes a model-chosen result key, every state key a tool writes is
marked as agent-written; `writeOutput`, `writeJson`, `writeXml` and
`executeDatabase` then refuse to consume it unless the step carries
`allowAgentData true`. The mark clears as soon as an ordinary step rewrites the
key. Threat model and design: [docs/design/ai-agent-tool-use.md](docs/design/ai-agent-tool-use.md).

### Files area

Every project has an isolated directory under the data sandbox, browsable in the UI
(**project → Files**): upload, download, create folders, delete. The file steps
(`readDirectory`, `writeOutput`, `parseJson`, `writeXml`, …) operate on this same
directory, so what a job produces is immediately visible there. In production the
sandbox root **must** be set via `STEP_DATA_ROOT`.

### Email (SMTP)

An admin configures the relay in **Administration → Email** (host, port, credentials,
TLS) and can send a test message to their own address. Once configured, failed
executions notify the members of the job's project and group.

### Accounts and security

- **TOTP two-factor**, enrolled from the profile page (QR code); once enabled, login
  returns a pending token and requires the 6-digit code
- **Personal API tokens** for scripting against the REST API
- Secrets (data source passwords, Slack URLs, Anthropic keys) are encrypted with
  AES-256-GCM using a key derived from `SECRET_KEY_BASE`

## Running locally

### Prerequisites

- **Elixir 1.15+** (with Erlang/OTP)
- **Node.js 18+** and **npm**
- **PostgreSQL** — either a native install **or** Docker (via the bundled `docker-compose.yml`)

#### Installing dependencies per Linux distro

**Arch / Manjaro**
```bash
sudo pacman -S elixir nodejs npm postgresql   # native Postgres
# or, to use Docker instead of native Postgres:
sudo pacman -S elixir nodejs npm docker docker-compose
```

**Debian / Ubuntu**
```bash
sudo apt update
sudo apt install -y elixir erlang nodejs npm postgresql postgresql-contrib
# Note: the elixir shipped by apt is often older than 1.15.
# For an up-to-date version, prefer asdf (https://asdf-vm.com) or the
# Erlang Solutions repo (https://www.erlang-solutions.com/downloads).
```

**Fedora / RHEL**
```bash
sudo dnf install -y elixir erlang nodejs npm postgresql postgresql-server
sudo postgresql-setup --initdb        # first time only (native install)
sudo systemctl enable --now postgresql
```

> **Tip:** the simplest, distro-independent path for the database is Docker.
> `docker-compose.yml` starts PostgreSQL 16 already configured with the
> `taskrunner` user/password/database that `apps/api/config/dev.exs` expects,
> so you can skip native Postgres setup entirely.

### Step by step (localhost)

**Option A — database via Docker (recommended)**

```bash
# 1. Start PostgreSQL in the background
docker compose up -d

# 2. Install deps (mix + npm) and run migrations
#    (db.create is a no-op here — the container already created the DB)
make setup

# 3. Start backend (:8080) and frontend (:4200) together
make dev
```

**Option B — native PostgreSQL**

```bash
# 1. Make sure the postgresql service is running, then:
#    installs deps, creates the taskrunner role/database, runs migrations
make setup

# 2. Start backend (:8080) and frontend (:4200) together
make dev
```

`make setup` runs `deps` (mix + npm) and `db.setup` (create role/database +
migrate + **seed the default admin**). In Option A the role/database creation
step just no-ops because the container already provides them; migrations and
seeding still run against the container.

Open **http://localhost:4200** once both processes are up.

### First login

The app requires authentication — you land on a login screen. `make setup`
(and `make db.seed`) creates an admin user with a **freshly generated random
password**, printed once to the terminal when it is created:

```
┌──────────────────────────────────────────────────────────────┐
│  Admin created — SAVE THE PASSWORD (it is not recoverable)    │
├──────────────────────────────────────────────────────────────┤
  email:    admin@cartograph.local
  password: 3f9a1c...   ← copy this from your terminal
  ...
```

The stored password is Bcrypt-hashed, so **the plaintext is shown only at
creation time — copy it from the seed output**. Log in with it, then change the
password and create your own users from the admin area.

The seed (`apps/api/priv/repo/seeds.exs`) is idempotent: if the admin already
exists, re-running `make db.seed` leaves the password untouched (nothing is
printed). To get a brand-new password, recreate the database with
`make db.reset`.

### Useful commands

```bash
make dev          # backend + frontend in parallel, with prefixed logs
make backend      # Phoenix only (port 8080)
make frontend     # Angular only (port 4200)
make desktop      # build the web app and launch the Electron desktop client
make desktop.build # package a portable Linux AppImage
make db.setup     # create role/database + migrations + seed admin
make db.migrate   # run pending migrations
make db.seed      # create the default admin user (idempotent)
make db.reset     # drop and recreate the database (includes seed)
make restart      # stop and restart backend + frontend
make restart.be   # stop and restart backend only
make security     # sobelow + mix deps.audit + npm audit (runtime deps)
make stop         # kill whatever is on ports 8080 and 4200
make clean        # remove build artifacts
make help         # list all targets
```

### Test flow

1. Open `http://localhost:4200` and **log in** as the seeded admin
   (`admin@cartograph.local`, password printed by `make setup` / `make db.seed`)
2. Create a group and a project (left sidebar)
3. Inside the project, click **New job** — the sample DSL is prefilled
4. Click **Run** → you are taken to the execution screen
5. Watch the visual pipeline and logs in real time
6. Try **Stop** (during the `transform` step) and **Re-run**

## Desktop app (Electron)

`apps/desktop` packages the Angular dashboard as a desktop client that talks to
a Cartograph backend. It is a **client of a service**: the backend URL is
configurable at runtime — from the **Server address** entry on the login screen
or the user menu — so a single build can point at any server (default
`http://localhost:8080`).

```bash
# with a backend reachable (e.g. `make backend`), from the repo root:
make desktop        # builds apps/web (electron config) and opens the window
make desktop.build  # packages a portable AppImage → apps/desktop/dist/
```

Under the hood it serves the built SPA over a custom `app://cartograph`
protocol (a stable origin whitelisted in the backend's CORS and socket
`check_origin`), uses hash-based routing, and injects the backend config at
runtime via an Electron preload bridge. See
[`apps/desktop/README.md`](apps/desktop/README.md) for the full details and how
to additionally produce a `.deb`.

## Structure

```
cartograph/
├── apps/
│   ├── api/                        ← Elixir/Phoenix
│   │   ├── lib/cartograph_backend/
│   │   │   ├── accounts/           # Users, sessions, TOTP, API tokens
│   │   │   ├── agents/             # Anthropic client, credentials, pricing
│   │   │   ├── data_sources/       # Postgres/MySQL connections + project assignment
│   │   │   ├── dsl/                # Lexer + parser (NimbleParsec) + Expander
│   │   │   ├── engine/             # ExecutorWorker (Oban), CronScheduler, LogBroadcaster
│   │   │   ├── executions/         # Execution and step lifecycle
│   │   │   ├── groups/             # Context: Group, Project (CRUD + cycle detection)
│   │   │   ├── mailing/            # SMTP settings, emails, failure notifications
│   │   │   ├── steps/              # One module per step + SafePath (sandbox)
│   │   │   ├── tasks/              # Context: TaskDefinition, TaskExecution, StepExecution
│   │   │   ├── webhooks/           # Slack webhooks per project
│   │   │   ├── files.ex            # Project file sandbox
│   │   │   ├── vault.ex            # AES-256-GCM for secrets at rest
│   │   │   ├── system_metrics.ex   # CPU/memory/disk/Oban for the monitoring page
│   │   │   └── metrics.ex          # Aggregated queries for the dashboard
│   │   └── lib/cartograph_backend_web/
│   │       ├── controllers/        # GroupController, ProjectController, TaskController, etc.
│   │       ├── graphql/            # Absinthe schema + resolvers
│   │       └── channels/           # UserSocket (WebSocket subscriptions)
│   ├── web/                        ← Angular 18
│   │   └── src/app/
│   │       ├── components/         # All components (dashboard, group, project, execution, etc.)
│   │       ├── services/           # ApiService, GraphQLService, NavContextService, ThemeService
│   │       └── graphql/            # Typed queries, mutations, and subscriptions
│   └── desktop/                    ← Electron desktop client (wraps apps/web)
│       └── electron/               # main + preload + config (app:// protocol, runtime backend config)
├── docker-compose.yml              # PostgreSQL 16 for local development
├── Makefile
└── LICENSE                         # MIT
```

## REST API

Every route requires authentication (bearer token from login, or a personal API token),
except the two login routes marked *public*.

**Auth & account**

| Method | Path | Description |
|--------|---------|-----------|
| POST | `/api/auth/login` | *public* — log in (may answer `totp_required` + `pendingToken`) |
| POST | `/api/auth/2fa/verify` | *public* — finish login with the 6-digit code |
| GET | `/api/auth/me` | current user |
| GET | `/api/auth/2fa/setup` | generate TOTP secret + provisioning URI |
| POST | `/api/auth/2fa/enable` | confirm the code and enable 2FA |
| DELETE | `/api/auth/2fa/disable` | disable 2FA |
| GET&nbsp;/&nbsp;POST | `/api/tokens` | list / create personal API tokens |
| DELETE | `/api/tokens/:id` | revoke a token |

**Jobs & executions**

| Method | Path | Description |
|--------|---------|-----------|
| GET | `/api/tasks` | list jobs (accepts `?projectId=`) |
| POST | `/api/tasks` | create job (validates DSL) |
| PUT | `/api/tasks/:id` | update job |
| DELETE | `/api/tasks/:id` | delete job |
| POST | `/api/tasks/:id/run` | trigger execution |
| GET | `/api/tasks/:id/flow` | expanded flow of one job (steps, `use`, if/else) |
| GET | `/api/tasks/graph` | cross-job dependency graph |
| GET | `/api/tasks/steps` | available steps |
| GET | `/api/executions` | list executions |
| GET | `/api/executions/:id` | execution + steps |
| GET | `/api/executions/:id/logs` | logs (history) |
| GET | `/api/executions/:id/logs/stream` | live logs (SSE) |
| POST | `/api/executions/:id/stop` | request stop |

**Groups & projects**

| Method | Path | Description |
|--------|---------|-----------|
| GET | `/api/groups` | list groups (flat — frontend builds the tree) |
| POST | `/api/groups` | create group |
| GET | `/api/groups/:id` | group detail |
| PUT | `/api/groups/:id` | update (detects cycle if parentId changes) |
| DELETE | `/api/groups/:id` | delete group |
| GET | `/api/projects` | list projects (accepts `?groupId=`) |
| POST | `/api/projects` | create project |
| GET | `/api/projects/:id` | project detail |
| PUT | `/api/projects/:id` | update project |
| DELETE | `/api/projects/:id` | delete project |

**Users & members**

| Method | Path | Description |
|--------|---------|-----------|
| GET | `/api/users` | list users (admin) |
| POST | `/api/users` | create user (admin) |
| PUT | `/api/users/:id` | update user (admin) |
| DELETE | `/api/users/:id` | delete user (admin) |
| GET | `/api/users/pickable` | users assignable as members |
| GET | `/api/access-levels` | reference data for the member picker |
| GET&nbsp;/&nbsp;POST | `/api/groups/:group_id/members` | list / add group members |
| DELETE | `/api/groups/:group_id/members/:user_id` | remove group member |
| GET&nbsp;/&nbsp;POST | `/api/projects/:project_id/members` | list / add project members |
| DELETE | `/api/projects/:project_id/members/:user_id` | remove project member |
| GET&nbsp;/&nbsp;POST | `/api/tasks/:task_id/members` | list / add job members |
| DELETE | `/api/tasks/:task_id/members/:user_id` | remove job member |

**Integrations & files**

| Method | Path | Description |
|--------|---------|-----------|
| GET&nbsp;/&nbsp;POST | `/api/data-sources` | list / create data source (admin) |
| PUT&nbsp;/&nbsp;DELETE | `/api/data-sources/:id` | update / delete data source (admin) |
| GET | `/api/data-sources/:id/health` | connectivity check |
| GET | `/api/projects/:project_id/data-sources` | sources assigned to the project |
| POST&nbsp;/&nbsp;DELETE | `/api/projects/:project_id/data-sources/:data_source_id` | assign / unassign |
| GET&nbsp;/&nbsp;PUT | `/api/smtp-settings` | read / update SMTP relay (admin) |
| POST | `/api/smtp-settings/test` | send a test email |
| GET&nbsp;/&nbsp;POST | `/api/projects/:project_id/slack-webhooks` | list / create webhook (Navigator+ to write) |
| PUT&nbsp;/&nbsp;DELETE | `/api/projects/:project_id/slack-webhooks/:id` | update / delete webhook |
| GET&nbsp;/&nbsp;POST | `/api/projects/:project_id/anthropic-credentials` | list / create credential |
| PUT&nbsp;/&nbsp;DELETE | `/api/projects/:project_id/anthropic-credentials/:id` | update / delete credential |
| GET | `/api/projects/:project_id/files` | list the project sandbox |
| POST | `/api/projects/:project_id/files` | upload a file |
| POST | `/api/projects/:project_id/files/mkdir` | create a folder |
| GET | `/api/projects/:project_id/files/download` | download a file |
| DELETE | `/api/projects/:project_id/files` | delete a file or folder |

**System**

| Method | Path | Description |
|--------|---------|-----------|
| GET | `/api/system/metrics` | CPU, memory, disk, Oban queues |
| GET | `/api/system/health` | health check |

## GraphQL

- **Endpoint:** `POST /graphql`
- **Playground:** `GET /graphiql` (dev only)
- **Subscriptions:** `ws://localhost:8080/socket/websocket`

Available queries: `groups`, `group`, `projects`, `tasks`, `task`, `executions`, `execution`, `executionSteps`, `executionLogs`, `dashboardMetrics`

Mutations: `createGroup`, `updateGroup`, `deleteGroup`, `createProject`, `updateProject`, `deleteProject`, `createTask`, `updateTask`, `deleteTask`, `runTask`, `stopExecution`

Subscriptions:

| Subscription | Pushes |
|--------------|--------|
| `executionLog(executionId)` | each new log line of an execution |
| `executionStatus(executionId)` | status changes of an execution |
| `taskExecutionUpdated(taskId)` | executions of one job — drives the live graph |
| `stepUpdated(executionId)` | per-step status, including agent token usage |

Step results expose `agentUsage` (model, input/output tokens, cache tokens, estimated
cost, stop reason, duration) for steps executed by the `agent` step.

## Clustering (production)

Set the `CLUSTER_STRATEGY` variable to enable automatic clustering via libcluster:

```bash
# Kubernetes headless service
CLUSTER_STRATEGY=k8s
K8S_SERVICE_NAME=cartograph-headless
K8S_APP_NAME=cartograph_backend

# Docker Compose / bare metal (same network)
CLUSTER_STRATEGY=gossip
GOSSIP_SECRET=shared_secret
```

Without the variable, it starts as a single node. Oban ensures jobs are not run more than once across nodes.

## Environment variables (production)

| Variable | Description |
|----------|-----------|
| `DATABASE_URL` | **required** — `ecto://user:pass@host/db` |
| `SECRET_KEY_BASE` | **required** — cookies/tokens **and** the secrets vault key (`mix phx.gen.secret`) |
| `STEP_DATA_ROOT` | **required** — persistent directory for job data, e.g. `/var/lib/cartograph/data` |
| `PHX_HOST` | public hostname |
| `PHX_SERVER` | `true` to enable the HTTP server in releases |
| `POOL_SIZE` | connection pool size (default: 10) |
| `ECTO_IPV6` | `true`/`1` to connect to the database over IPv6 |
| `DNS_CLUSTER_QUERY` | DNS query for node discovery |
| `CLUSTER_STRATEGY` | `k8s`, `gossip`, or omit for single-node |

> **Careful with `SECRET_KEY_BASE`:** the encryption key for stored secrets (data source
> passwords, Slack URLs, Anthropic keys) is derived from it. Changing it makes every
> stored secret undecryptable — they have to be registered again.
>
> Without `STEP_DATA_ROOT` the release refuses to boot: in a release the working
> directory is not the source tree, so the `data` default used in dev would land
> somewhere volatile.

## Documentation

Design docs live in [`docs/design/`](docs/design/README.md) — they describe how each
subsystem works today (API surfaces, authorization, DSL execution engine, error
contract, AI agent jobs). The running app also ships a **Docs** page in the sidebar
with the DSL reference.

## License

Released under the [MIT License](LICENSE). © 2026 Vanilton Alves dos Santos Filho.
