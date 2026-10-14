# The opendebate-cab image: the `cab` release, listening on 4000. Policy
# and Terms are not baked in: the server mounts its legal/ folder and
# points LEGAL_DIR at it.

ARG ELIXIR_IMAGE=hexpm/elixir:1.18.5-erlang-27.3.4.18-debian-bookworm-20261005-slim
ARG RUNTIME_IMAGE=debian:bookworm-20261005-slim

# ---- build -------------------------------------------------------------
FROM ${ELIXIR_IMAGE} AS build

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential git ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

# dependencies first, so code changes reuse this layer
COPY mix.exs mix.lock ./
COPY apps/core/mix.exs apps/core/mix.exs
COPY apps/cab/mix.exs apps/cab/mix.exs
COPY config/config.exs config/prod.exs config/
RUN mix deps.get --only prod && mix deps.compile

COPY apps apps
COPY config/runtime.exs config/
RUN mix compile

# cab's assets need the compiled app (colocated hooks), then digesting
RUN cd apps/cab && mix assets.setup && mix assets.deploy

RUN mix release cab

# ---- run ---------------------------------------------------------------
FROM ${RUNTIME_IMAGE}

RUN apt-get update \
 && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates curl \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --create-home --home-dir /app opendebate

WORKDIR /app
ENV LANG=C.UTF-8 PHX_SERVER=true MIX_ENV=prod

COPY --from=build --chown=opendebate:opendebate /app/_build/prod/rel/cab ./
USER opendebate
# club logos (CAB_UPLOADS_DIR); a volume mounted here starts out owned
# by the app user
RUN mkdir /app/uploads
EXPOSE 4000
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD curl -fsS http://localhost:4000/healthz || exit 1

CMD ["/app/bin/cab", "start"]
