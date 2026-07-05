## Cartograph — Development Makefile
##
## Prerequisites:
##   - Elixir 1.15+  (pacman -S elixir)
##   - Node.js 18+   (pacman -S nodejs npm)
##   - PostgreSQL     (pacman -S postgresql) OR Docker (docker compose)

BACKEND  := apps/api
FRONTEND := apps/web

DB_USER := taskrunner
DB_PASS := taskrunner
DB_NAME := taskrunner

GREEN  := \033[0;32m
YELLOW := \033[1;33m
RED    := \033[0;31m
CYAN   := \033[0;36m
NC     := \033[0m

.DEFAULT_GOAL := help

# ── Help ──────────────────────────────────────────────────────────────────────

.PHONY: help
help:
	@printf "$(GREEN)Cartograph$(NC) — distributed task runner\n\n"
	@printf "$(CYAN)First run:$(NC)\n"
	@printf "  make setup          Install deps + create database + run migrations\n\n"
	@printf "$(CYAN)Development:$(NC)\n"
	@printf "  make dev            Start backend and frontend together\n"
	@printf "  make backend        Phoenix only  (port 8080)\n"
	@printf "  make frontend       Angular only  (port 4200)\n\n"
	@printf "$(CYAN)Database:$(NC)\n"
	@printf "  make db.setup       Create role/database, run migrations, and seed the admin\n"
	@printf "  make db.migrate     Run pending migrations\n"
	@printf "  make db.seed        Create the default admin user (idempotent)\n"
	@printf "  make db.reset       Recreate the database from scratch (includes seed)\n\n"
	@printf "$(CYAN)Utilities:$(NC)\n"
	@printf "  make restart        Stop and restart backend + frontend\n"
	@printf "  make restart.be     Stop and restart backend only\n"
	@printf "  make deps           Install dependencies (mix + npm)\n"
	@printf "  make clean          Remove build artifacts\n"

# ── Setup ─────────────────────────────────────────────────────────────────────

.PHONY: setup
setup: deps db.setup
	@printf "\n$(GREEN)✔ Done!$(NC) Run $(YELLOW)make dev$(NC) to start.\n"

.PHONY: deps
deps:
	@printf "$(YELLOW)→ Elixir deps...$(NC)\n"
	cd $(BACKEND) && mix deps.get
	@printf "$(YELLOW)→ Node.js deps...$(NC)\n"
	cd $(FRONTEND) && npm install

# ── Database ──────────────────────────────────────────────────────────────────

.PHONY: db.setup
db.setup: db.create db.migrate db.seed

.PHONY: db.seed
db.seed:
	@printf "$(YELLOW)→ Seeding data (default admin)...$(NC)\n"
	cd $(BACKEND) && mix run priv/repo/seeds.exs

.PHONY: db.create
db.create:
	@printf "$(YELLOW)→ Creating role and database...$(NC)\n"
	@sudo -u postgres psql \
	  -c "CREATE ROLE $(DB_USER) WITH LOGIN PASSWORD '$(DB_PASS)' CREATEDB;" \
	  2>/dev/null || true
	@sudo -u postgres psql \
	  -c "CREATE DATABASE $(DB_NAME) OWNER $(DB_USER);" \
	  2>/dev/null || true
	@printf "$(GREEN)✔ Database ready$(NC)\n"

.PHONY: db.migrate
db.migrate:
	@printf "$(YELLOW)→ Running migrations...$(NC)\n"
	cd $(BACKEND) && mix ecto.migrate

.PHONY: db.reset
db.reset:
	@printf "$(RED)→ Recreating database...$(NC)\n"
	cd $(BACKEND) && mix ecto.drop && mix ecto.create && mix ecto.migrate
	$(MAKE) db.seed

# ── Run ───────────────────────────────────────────────────────────────────────

.PHONY: backend
backend:
	cd $(BACKEND) && mix phx.server

.PHONY: frontend
frontend:
	cd $(FRONTEND) && npm start

.PHONY: dev
dev:
	@printf "$(GREEN)Starting Cartograph$(NC)\n"
	@printf "  Backend  → http://localhost:8080\n"
	@printf "  Frontend → http://localhost:4200\n\n"
	@trap 'kill 0' INT TERM; \
		(cd $(BACKEND)  && mix phx.server 2>&1 | sed 's/^/[be] /') & \
		(cd $(FRONTEND) && npm start      2>&1 | sed 's/^/[fe] /') & \
		wait

# ── Restart ───────────────────────────────────────────────────────────────────

.PHONY: stop
stop:
	@printf "$(YELLOW)→ Stopping processes...$(NC)\n"
	@fuser -k 8080/tcp 2>/dev/null || true
	@fuser -k 4200/tcp 2>/dev/null || true
	@sleep 1
	@printf "$(GREEN)✔ Processes terminated$(NC)\n"

.PHONY: restart
restart: stop
	@printf "$(GREEN)→ Restarting Cartograph$(NC)\n"
	@printf "  Backend  → http://localhost:8080\n"
	@printf "  Frontend → http://localhost:4200\n\n"
	@trap 'kill 0' INT TERM; \
		(cd $(BACKEND)  && mix phx.server 2>&1 | sed 's/^/[be] /') & \
		(cd $(FRONTEND) && npm start      2>&1 | sed 's/^/[fe] /') & \
		wait

.PHONY: restart.be
restart.be:
	@printf "$(YELLOW)→ Stopping backend...$(NC)\n"
	@fuser -k 8080/tcp 2>/dev/null || true
	@sleep 1
	@printf "$(GREEN)→ Restarting backend$(NC) → http://localhost:8080\n"
	cd $(BACKEND) && mix phx.server

# ── Clean ─────────────────────────────────────────────────────────────────────

.PHONY: clean
clean:
	cd $(BACKEND)  && mix clean
	rm -rf $(FRONTEND)/dist $(FRONTEND)/.angular
