# The opendebate-cab image: the `full` release, cab on 4000 and the public
# site on 4001. Policy and Terms and the tenant folder are not baked in:
# the server mounts them (LEGAL_DIR, TENANT_DIR).

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
COPY apps/public/mix.exs apps/public/mix.exs
COPY config/config.exs config/prod.exs config/
RUN mix deps.get --only prod && mix deps.compile

COPY apps apps
COPY config/runtime.exs config/
RUN mix compile

# Tailwind's binary, fetched with curl: the tailwind package's own
# download (Erlang httpc) refuses GitHub's release redirects
# (header_too_long). It lands where the package looks for it, so
# assets.setup finds it in place; the version is config.exs's.
ARG TARGETARCH
RUN TW=$(sed -n '/^config :tailwind,/,/^$/s/.*version: "\([0-9.]*\)".*/\1/p' config/config.exs) \
 && case "${TARGETARCH:-amd64}" in arm64) T=linux-arm64 ;; *) T=linux-x64 ;; esac \
 && test -n "$TW" \
 && mkdir -p _build \
 && curl -fsSL --retry 3 -o "_build/tailwind-$T-$TW" \
      "https://github.com/tailwindlabs/tailwindcss/releases/download/v$TW/tailwindcss-$T" \
 && chmod +x "_build/tailwind-$T-$TW"

# cab's assets need the compiled app (colocated hooks), then digesting
RUN cd apps/cab && mix assets.setup && mix assets.deploy

RUN mix release full

# ---- run ---------------------------------------------------------------
FROM ${RUNTIME_IMAGE}

RUN apt-get update \
 && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates curl \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --create-home --home-dir /app opendebate

WORKDIR /app
ENV LANG=C.UTF-8 PHX_SERVER=true MIX_ENV=prod

COPY --from=build --chown=opendebate:opendebate /app/_build/prod/rel/full ./
USER opendebate
# the public site's news images (PUBLIC_UPLOADS_DIR) and cab's club logos
# (CAB_UPLOADS_DIR); a volume mounted here starts out owned by the app user
RUN mkdir /app/uploads /app/cab-uploads
EXPOSE 4000 4001
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD curl -fsS http://localhost:4000/healthz && curl -fsS http://localhost:4001/healthz || exit 1

CMD ["/app/bin/full", "start"]
