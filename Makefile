# What `make release` releases (scripts/release reads these)
RELEASE_NAME      = opendebate-cab
RELEASE_REPO      = Ukrainian-Debate-Dev-Community/opendebate-cab
RELEASE_CI        = ci.yml
RELEASE_FILES     = mix.exs apps/core/mix.exs apps/cab/mix.exs apps/public/mix.exs
RELEASE_CHANGELOG = CHANGELOG.md
IMAGE             = ghcr.io/ukrainian-debate-dev-community/opendebate-cab
RELEASE_ARTIFACT  = the image $(IMAGE):v{version} (release workflow)

RUN_DIR = .run
# Homebrew's postgresql@16 psql (survives upgrades), else psql on PATH
PSQL   ?= $(shell p="$$(brew --prefix postgresql@16 2>/dev/null)/bin/psql"; [ -x "$$p" ] && echo "$$p" || echo psql)
NIX     = nix develop --command
# The engine reads engine/.env; without one it starts with these
# development settings and the secret cab signs with (ENGINE_JWT_SECRET
# from the repo's .env, else cab's dev default). Prefix for a shell line
# that then runs in engine/.
ENGINE_SHELL = set -a; [ -f .env ] && . ./.env; set +a; cd engine; \
	[ -f .env ] || export JWT_SECRET="$${ENGINE_JWT_SECRET:-insecure-dev-engine-secret-not-for-production}" PORT=3100 \
		NODE_ENV=development DB_HOST=localhost DB_PORT=5432 DB_USER=postgres DB_PASSWORD=postgres \
		DB_DATABASE=cab_dev DB_TEST=cab_test;

.PHONY: setup dev build test test-all lint fmt clean release FORCE

# Targets named dev:<x> run against the local stack. GNU make 3.81 keeps
# the backslash of an escaped colon in .PHONY and prerequisite lists, so
# these depend on FORCE instead and call each other through $(MAKE).
FORCE:

# ---------------------------------------------------------------
# Standard targets
# ---------------------------------------------------------------

# Engine checkout and its packages, Elixir deps, the tailwind binary,
# databases. Tailwind is fetched with curl into _build, where the
# tailwind package looks: its own download (Erlang httpc) fails on
# GitHub's release redirects (header_too_long) and a checkout without
# the binary builds no CSS. The version is config.exs's.
setup:
	git submodule update --init
	cd engine && npm install
	@TW=$$(sed -n '/^config :tailwind,/,/^$$/s/.*version: "\([0-9.]*\)".*/\1/p' config/config.exs); \
	case "$$(uname -s)-$$(uname -m)" in \
		Darwin-arm64) T=macos-arm64 ;; Darwin-x86_64) T=macos-x64 ;; \
		Linux-aarch64|Linux-arm64) T=linux-arm64 ;; *) T=linux-x64 ;; \
	esac; \
	f="_build/tailwind-$$T-$$TW"; \
	if [ -x "$$f" ]; then echo "tailwind $$TW already in $$f"; \
	else mkdir -p _build && curl -fsSL --retry 3 -o "$$f" \
		"https://github.com/tailwindlabs/tailwindcss/releases/download/v$$TW/tailwindcss-$$T" \
		&& chmod +x "$$f" && echo "tailwind $$TW -> $$f"; fi
	$(NIX) sh -c 'mix deps.get && mix ecto.create && mix ecto.migrate'

# make dev = make dev:up
dev:
	@$(MAKE) --no-print-directory dev:up

build:
	$(NIX) mix compile --warnings-as-errors

test:
	$(NIX) sh -c 'MIX_ENV=test mix test'

# Everything that runs without the local stack (make dev:e2e needs it):
# the unit tests and the release script's own checks
test-all: test
	python3 scripts/release --self-test

lint:
	$(NIX) sh -c 'mix format --check-formatted && (cd apps/cab && MIX_ENV=test mix gettext.extract --check-up-to-date) && (cd apps/public && MIX_ENV=test mix gettext.extract --check-up-to-date) && mix hex.audit'

fmt:
	$(NIX) mix format

clean:
	rm -rf _build $(RUN_DIR)

# ---------------------------------------------------------------
# Local dev stack: engine (node, :3100), cab (:4000) and the public
# site (:4001), the last two in one phoenix node
# ---------------------------------------------------------------

# Start the engine and the phoenix node in the background. Logs go to
# .run/*.log. The public site's tenant is TENANT_DIR from .env, else the
# neutral test tenant.
dev\:up: FORCE
	@mkdir -p $(RUN_DIR)
	@if lsof -ti :3100 >/dev/null 2>&1; then \
		echo "engine   already running on :3100"; \
	else \
		($(ENGINE_SHELL) nohup node src/app.js >> ../$(RUN_DIR)/engine.log 2>&1 &) \
		&& echo "engine   starting on :3100  (log: $(RUN_DIR)/engine.log)"; \
	fi
	@if lsof -ti :4000 >/dev/null 2>&1; then \
		echo "cab      already running on :4000"; \
	else \
		(nohup $(NIX) mix phx.server >> $(RUN_DIR)/cab.log 2>&1 &) \
		&& echo "cab      starting on :4000, public on :4001  (log: $(RUN_DIR)/cab.log, first boot may take a minute)"; \
	fi
	@printf "waiting for cab and the public site"
	@for i in $$(seq 1 90); do \
		if curl -s -o /dev/null --max-time 2 http://localhost:4000/ 2>/dev/null \
			&& curl -s -o /dev/null --max-time 2 http://localhost:4001/ 2>/dev/null; then \
			echo " ready"; echo "open http://localhost:4000/ (cab) and http://localhost:4001/ (public)"; exit 0; \
		fi; printf "."; sleep 2; \
	done; echo " not up after 3 min - check: make dev:logs"

# Stop the services (kills whatever listens on :3100 / :4000 / :4001).
dev\:down: FORCE
	@-lsof -ti :4000 2>/dev/null | xargs kill 2>/dev/null; true
	@-lsof -ti :4001 2>/dev/null | xargs kill 2>/dev/null; true
	@-lsof -ti :3100 2>/dev/null | xargs kill 2>/dev/null; true
	@echo "stopped (ports 3100, 4000 and 4001 freed)"

dev\:restart: FORCE
	@$(MAKE) --no-print-directory dev:down
	@$(MAKE) --no-print-directory dev:up

# Wipe the engine's, cab's and the public site's databases, reseed the
# engine, migrate, restart the stack and load fresh demo data around
# your own account:
#   make dev:fresh DEV_USER=<your cab username>
dev\:fresh: FORCE
	@test -n "$(DEV_USER)" || { echo "usage: make dev:fresh DEV_USER=<your cab username>"; exit 1; }
	@$(MAKE) --no-print-directory dev:down
	@echo "== wiping engine db (cab_dev) =="
	$(PSQL) -d postgres -c 'DROP DATABASE IF EXISTS cab_dev;' -c 'CREATE DATABASE cab_dev OWNER postgres;'
	$(ENGINE_SHELL) npx sequelize-cli db:migrate && npx sequelize-cli db:seed:all
	@echo "== wiping cab's and the public site's dbs (cab_gateway_dev, public_dev) =="
	$(NIX) sh -c 'mix ecto.drop --force && mix ecto.create && mix ecto.migrate'
	@$(MAKE) --no-print-directory dev:up
	@echo "== loading demo data =="
	apps/cab/priv/prime_demo.sh $(DEV_USER)
	@echo "fresh demo ready: http://localhost:4000/ and http://localhost:4001/"

# Record lifecycle facts on cab session rows that predate them.
# Safe to re-run; needs the engine up.
dev\:backfill: FORCE
	$(NIX) mix cab.backfill_sessions

# The full session roundtrip against the running local stack (make
# dev:up; make dev:fresh first for a clean database). Re-runnable.
dev\:e2e: FORCE
	apps/cab/priv/walkthrough_rest.sh

# Every key page as an iPhone 15 against the running stack (make dev:up):
# fails when a page scrolls sideways. Not part of CI.
# Signs in as DEV_USER: make dev:phone DEV_USER=<a cab username>
dev\:phone: FORCE
	@test -n "$(DEV_USER)" || { echo "usage: make dev:phone DEV_USER=<a cab username>"; exit 1; }
	DEV_USER=$(DEV_USER) PATH="$(dir $(PSQL)):$$PATH" uv run tools/phone/phone_check.py

# Refresh the engine's API description served at /api/docs from the
# pinned engine (after the engine pin moves)
dev\:api-docs: FORCE
	cp engine/docs/openapi.yml apps/cab/priv/api/engine.yml

# Load test against the running local stack (make dev:up first)
dev\:stress: FORCE
	ulimit -n 8192 && uv run tools/stress/stress.py

dev\:logs: FORCE
	@mkdir -p $(RUN_DIR) && touch $(RUN_DIR)/engine.log $(RUN_DIR)/cab.log
	tail -n 40 -f $(RUN_DIR)/engine.log $(RUN_DIR)/cab.log

dev\:status: FORCE
	@if lsof -ti :3100 >/dev/null 2>&1; then echo "engine   up   :3100"; else echo "engine   down :3100"; fi
	@if lsof -ti :4000 >/dev/null 2>&1; then echo "cab      up   :4000"; else echo "cab      down :4000"; fi
	@if lsof -ti :4001 >/dev/null 2>&1; then echo "public   up   :4001"; else echo "public   down :4001"; fi

# Move the engine pin to the engine's latest release tag (what the
# nightly workflow does). REF=<ref> pins another ref instead, e.g.
# make dev:bump-engine REF=origin/nightly
dev\:bump-engine: FORCE
	git -C engine fetch --quiet --tags origin
	@ref="$(REF)"; [ -n "$$ref" ] || ref=$$(git -C engine tag -l 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$$' | sort -V | tail -1); \
	test -n "$$ref" || { echo "the engine has no release tag yet: make dev:bump-engine REF=origin/nightly"; exit 1; }; \
	git -C engine checkout --quiet "$$ref" && echo "engine at $$ref"
	git -C engine log --oneline -1

# Build the release image locally (needs docker running)
dev\:image: FORCE
	docker build -t $(IMAGE):local .

# ---------------------------------------------------------------
# Releases: main moves only here, by fast-forward to a release commit
# on nightly. scripts/release (the same in every repo) does it all:
#   make release BUMP=patch|minor|major   (or VERSION=X.Y.Z)
#   make release BUMP=patch DRY_RUN=1     preview, changes nothing
#   make release RESUME=1                 finish an interrupted release
# ---------------------------------------------------------------

release:
	@python3 scripts/release --name '$(RELEASE_NAME)' --repo '$(RELEASE_REPO)' \
		--ci '$(RELEASE_CI)' --files '$(RELEASE_FILES)' --changelog '$(RELEASE_CHANGELOG)' \
		--artifact '$(RELEASE_ARTIFACT)' $(if $(BUMP),--bump '$(BUMP)') \
		$(if $(VERSION),--version '$(VERSION)') $(if $(SINCE),--since '$(SINCE)') \
		$(if $(DRY_RUN),--dry-run) $(if $(RESUME),--resume)
