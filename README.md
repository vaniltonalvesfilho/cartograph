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
- **Execution**: steps run sequentially via Oban workers
- **Live logs**: via SSE (REST) and GraphQL subscriptions (WebSocket)
- **Visual pipeline**: GitLab CI-style view on the execution screen
- **Dependency graph**: interactive DAG with elkjs (ELK) layout on the job listing
- **Authorization**: access levels (Wayfarer → Cartographer) cascading group → project → job
- **i18n**: interface in Portuguese and English (switch in real time)
- **Dual API**: REST and GraphQL coexist — REST kept for compatibility
- **Theme**: light/dark, persisted in localStorage

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
make db.setup     # create role/database + migrations + seed admin
make db.migrate   # run pending migrations
make db.seed      # create the default admin user (idempotent)
make db.reset     # drop and recreate the database (includes seed)
make restart      # stop and restart backend + frontend
make restart.be   # stop and restart backend only
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

## Structure

```
cartograph/
├── apps/
│   ├── api/                        ← Elixir/Phoenix
│   │   ├── lib/cartograph_backend/
│   │   │   ├── dsl/                # Lexer + parser (NimbleParsec) + Expander
│   │   │   ├── engine/             # ExecutorWorker (Oban), CronScheduler, LogBroadcaster
│   │   │   ├── groups/             # Context: Group, Project (CRUD + cycle detection)
│   │   │   ├── tasks/              # Context: TaskDefinition, TaskExecution, StepExecution
│   │   │   └── metrics.ex          # Aggregated queries for the dashboard
│   │   └── lib/cartograph_backend_web/
│   │       ├── controllers/        # GroupController, ProjectController, TaskController, etc.
│   │       ├── graphql/            # Absinthe schema + resolvers
│   │       └── channels/           # UserSocket (WebSocket subscriptions)
│   └── web/                        ← Angular 18
│       └── src/app/
│           ├── components/         # All components (dashboard, group, project, execution, etc.)
│           ├── services/           # ApiService, GraphQLService, NavContextService, ThemeService
│           └── graphql/            # Typed queries, mutations, and subscriptions
├── docker-compose.yml              # PostgreSQL 16 for local development
├── Makefile
└── LICENSE                         # MIT
```

## REST API

| Method | Path | Description |
|--------|---------|-----------|
| GET | `/api/tasks` | list jobs (accepts `?projectId=`) |
| POST | `/api/tasks` | create job (validates DSL) |
| PUT | `/api/tasks/:id` | update job |
| DELETE | `/api/tasks/:id` | delete job |
| POST | `/api/tasks/:id/run` | trigger execution |
| GET | `/api/tasks/steps` | available steps |
| GET | `/api/groups` | list groups (flat — frontend builds the tree) |
| POST | `/api/groups` | create group |
| PUT | `/api/groups/:id` | update (detects cycle if parentId changes) |
| DELETE | `/api/groups/:id` | delete group |
| GET | `/api/projects` | list projects (accepts `?groupId=`) |
| POST | `/api/projects` | create project |
| PUT | `/api/projects/:id` | update project |
| DELETE | `/api/projects/:id` | delete project |
| GET | `/api/executions` | list executions |
| GET | `/api/executions/:id` | execution + steps |
| GET | `/api/executions/:id/logs` | logs (history) |
| GET | `/api/executions/:id/logs/stream` | live logs (SSE) |
| POST | `/api/executions/:id/stop` | request stop |

## GraphQL

- **Endpoint:** `POST /graphql`
- **Playground:** `GET /graphiql` (dev only)
- **Subscriptions:** `ws://localhost:8080/socket/websocket`

Available queries: `groups`, `group`, `projects`, `tasks`, `task`, `executions`, `execution`, `executionSteps`, `executionLogs`, `dashboardMetrics`

Mutations: `createGroup`, `updateGroup`, `deleteGroup`, `createProject`, `updateProject`, `deleteProject`, `createTask`, `updateTask`, `deleteTask`, `runTask`, `stopExecution`

Subscriptions: `executionLog(executionId)`, `executionStatus(executionId)`

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
| `DATABASE_URL` | `ecto://user:pass@host/db` |
| `SECRET_KEY_BASE` | key for cookies/tokens (`mix phx.gen.secret`) |
| `PHX_HOST` | public hostname |
| `PHX_SERVER` | `true` to enable the HTTP server in releases |
| `POOL_SIZE` | connection pool size (default: 10) |
| `CLUSTER_STRATEGY` | `k8s`, `gossip`, or omit for single-node |

## License

Released under the [MIT License](LICENSE). © 2026 Vanilton Alves dos Santos Filho.
