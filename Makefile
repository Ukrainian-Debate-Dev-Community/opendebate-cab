RUN_DIR = .run
# Homebrew's postgresql@16 psql (survives upgrades), else psql on PATH
PSQL   ?= $(shell p="$$(brew --prefix postgresql@16 2>/dev/null)/bin/psql"; [ -x "$$p" ] && echo "$$p" || echo psql)
NIX     = nix develop --command

.PHONY: setup dev build test test-all lint fmt clean release FORCE

# Targets named dev:<x> run against the local stack. GNU make 3.81 keeps
# the backslash of an escaped colon in .PHONY and prerequisite lists, so
# these depend on FORCE instead and call each other through $(MAKE).
FORCE:

# ---------------------------------------------------------------
# Standard targets
# ---------------------------------------------------------------

# Engine checkout and its packages, Elixir deps, databases
setup:
	git submodule update --init
	cd engine && npm install
	$(NIX) sh -c 'mix deps.get && mix ecto.create && mix ecto.migrate'

# make dev = make dev:up
dev:
	@$(MAKE) --no-print-directory dev:up

build:
	$(NIX) mix compile --warnings-as-errors

test:
	$(NIX) sh -c 'MIX_ENV=test mix test'

# Everything that runs without the local stack (make dev:e2e needs it)
test-all: test

lint:
	$(NIX) sh -c 'mix format --check-formatted && (cd apps/cab && MIX_ENV=test mix gettext.extract --check-up-to-date) && mix hex.audit'

fmt:
	$(NIX) mix format

clean:
	rm -rf _build $(RUN_DIR)

# ---------------------------------------------------------------
# Local dev stack: engine (node, :3100) + cab (phoenix, :4000)
# ---------------------------------------------------------------

# Start both services in the background. Logs go to .run/*.log.
dev\:up: FORCE
	@mkdir -p $(RUN_DIR)
	@if lsof -ti :3100 >/dev/null 2>&1; then \
		echo "engine   already running on :3100"; \
	else \
		(cd engine && nohup node src/app.js >> ../$(RUN_DIR)/engine.log 2>&1 &) \
		&& echo "engine   starting on :3100  (log: $(RUN_DIR)/engine.log)"; \
	fi
	@if lsof -ti :4000 >/dev/null 2>&1; then \
		echo "cab      already running on :4000"; \
	else \
		(nohup $(NIX) mix phx.server >> $(RUN_DIR)/cab.log 2>&1 &) \
		&& echo "cab      starting on :4000  (log: $(RUN_DIR)/cab.log, first boot may take a minute)"; \
	fi
	@printf "waiting for cab"
	@for i in $$(seq 1 60); do \
		if curl -s -o /dev/null --max-time 2 http://localhost:4000/ 2>/dev/null; then \
			echo " ready"; echo "open http://localhost:4000/"; exit 0; \
		fi; printf "."; sleep 2; \
	done; echo " not up after 2 min - check: make dev:logs"

# Stop the services (kills whatever listens on :3100 / :4000).
dev\:down: FORCE
	@-lsof -ti :4000 2>/dev/null | xargs kill 2>/dev/null; true
	@-lsof -ti :3100 2>/dev/null | xargs kill 2>/dev/null; true
	@echo "stopped (ports 3100 and 4000 freed)"

dev\:restart: FORCE
	@$(MAKE) --no-print-directory dev:down
	@$(MAKE) --no-print-directory dev:up

# Wipe BOTH databases, reseed the engine, migrate cab, restart
# the stack and load fresh demo data around your own account:
#   make dev:fresh DEV_USER=<your cab username>
dev\:fresh: FORCE
	@test -n "$(DEV_USER)" || { echo "usage: make dev:fresh DEV_USER=<your cab username>"; exit 1; }
	@$(MAKE) --no-print-directory dev:down
	@echo "== wiping engine db (cab_dev) =="
	$(PSQL) -d postgres -c 'DROP DATABASE IF EXISTS cab_dev;' -c 'CREATE DATABASE cab_dev OWNER postgres;'
	cd engine && npx sequelize-cli db:migrate && npx sequelize-cli db:seed:all
	@echo "== wiping cab db (cab_gateway_dev) =="
	$(NIX) sh -c 'mix ecto.drop --force && mix ecto.create && mix ecto.migrate'
	@$(MAKE) --no-print-directory dev:up
	@echo "== loading demo data =="
	apps/cab/priv/prime_demo.sh $(DEV_USER)
	@echo "fresh demo ready: http://localhost:4000/"

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
# Releases: master moves only here, by fast-forward to nightly
# ---------------------------------------------------------------

IMAGE = ghcr.io/ukrainian-debate-dev-community/opendebate-cab

# make release VERSION=v0.1.0 - from a clean nightly whose CI is green:
# fast-forward master, tag, push both; the tag publishes the image
release:
	@echo "$(VERSION)" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$$' || { echo "usage: make release VERSION=vX.Y.Z"; exit 1; }
	@[ -z "$$(git status --porcelain --untracked-files=no)" ] || { echo "the working tree has changes"; exit 1; }
	@[ "$$(git rev-parse --abbrev-ref HEAD)" = "nightly" ] || { echo "switch to nightly first"; exit 1; }
	@git fetch -q origin
	@[ "$$(git rev-parse HEAD)" = "$$(git rev-parse origin/nightly)" ] || { echo "nightly differs from origin/nightly: pull or push first"; exit 1; }
	@[ -z "$$(git tag -l $(VERSION))" ] && [ -z "$$(git ls-remote --tags origin refs/tags/$(VERSION))" ] || { echo "$(VERSION) already exists"; exit 1; }
	@[ "$$(gh run list --workflow ci.yml --commit $$(git rev-parse HEAD) --json conclusion -q '.[0].conclusion')" = "success" ] || { echo "CI on this commit is not green"; exit 1; }
	@echo "release $(VERSION): master -> $$(git rev-parse --short HEAD) ($$(git log -1 --format=%s)), tag $(VERSION), image $(IMAGE):$(VERSION)"
	@printf "type the version again to confirm: "; read answer < /dev/tty; [ "$$answer" = "$(VERSION)" ] || { echo "cancelled"; exit 1; }
	git push origin nightly:master
	git tag -a $(VERSION) -m $(VERSION)
	git push origin $(VERSION)
	@echo "pushed; the release workflow now builds $(IMAGE):$(VERSION)"
