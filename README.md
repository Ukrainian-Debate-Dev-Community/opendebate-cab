# opendebate-cab

The club cabinet of OpenDebate: debate clubs, their members and their
sessions, on top of the debate engine. An Elixir umbrella (Phoenix):

- `apps/core`: the engine client and the shared mailer
- `apps/cab`: the club cabinet, the web app on :4000

Dependencies point down only: cab -> core -> engine. cab and core know
nothing about the apps built on them; such apps pull this repo in and
depend on `apps/cab` and `apps/core`.

`engine/` is the debate engine, [opendebate-engine](https://github.com/Ukrainian-Debate-Dev-Community/opendebate-engine),
pinned as a git submodule. Policy and Terms are deployment documents,
read from `LEGAL_DIR` (in development, without it, from an
`opendebate-server` checkout next to this repo); without them the pages
answer 404.

## Getting started

```sh
make setup   # engine checkout and packages, Elixir deps, databases
make up      # engine on :3100, cab on :4000
make status  # what is running
make down
make test    # unit tests
make test-all
make test-phone DEV_USER=<username>  # every key page as an iPhone 15, against the running stack (make up)
```

The dev stack reads `.env` at the repo root (OAuth keys, engine secret,
`LEGAL_DIR`) and `engine/.env`. Tooling comes from `nix develop`.

## Branches and releases

- `nightly` is the default branch and the only target for pull requests;
  CI (`test`, `lint`, `guard`, `docker`) must pass. Every night a workflow
  moves the engine pin to the engine's latest main and opens a pull
  request into `nightly` when it changed.
- `master` moves only on a release: `make release VERSION=vX.Y.Z` from a
  clean `nightly` whose CI is green fast-forwards `master`, tags the
  commit and pushes both. The tag publishes the image
  `ghcr.io/ukrainian-debate-dev-community/opendebate-cab:vX.Y.Z` (and
  `:sha-<commit>`) with a GitHub release.
- `make image` builds the image locally (Docker needed).

The image runs the `cab` release on port 4000 and answers `GET /healthz`.
Before starting a new version run the migrations:

```sh
bin/cab eval "Cab.Release.migrate()"
```

## Production settings

| Variable | Needed | What |
|---|---|---|
| `DATABASE_URL` | yes | cab's database, `ecto://user:pass@host/db` |
| `SECRET_KEY_BASE` | yes | signs cookies |
| `PHX_HOST` | yes | cab's host, e.g. `cab.example.org` |
| `ENGINE_URL` | yes | the engine, e.g. `http://engine:3000` |
| `ENGINE_JWT_SECRET` | yes | shared with the engine's `JWT_SECRET`; the dev default is refused |
| `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET` | yes | sign-in with GitHub |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` | yes | sign-in with Google |
| `LEGAL_DIR` | yes | folder with `en/policy.md`, `en/terms.md` (and other languages); 404 without |
| `CAB_UPLOADS_DIR` | yes | folder for club logos, served at `/uploads`; in the image `/app/uploads`, a persistent volume kept in the backups |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD` | for mail | without `SMTP_HOST` mail is kept in memory and not sent |
| `MAIL_FROM` | for mail | `Name <address>`, e.g. `cab <noreply@example.org>` |
| `SESSION_COOKIE_DOMAIN` | no | e.g. `.example.org`, so sibling sites can read the sign-in |
| `RATE_LIMIT_ENABLED` | no | the JSON API's rate limit, `true` by default |
| `RATE_LIMIT_SIGNED_IN`, `RATE_LIMIT_ANONYMOUS` | no | requests per minute, 60 and 20 by default |
| `PHX_SERVER` | set by the image | starts the web server |
| `PORT` | no | 4000 by default |
| `POOL_SIZE` | no | the database pool, 10 by default |
| `ECTO_IPV6` | no | `true` to reach the database over IPv6 |
| `DNS_CLUSTER_QUERY` | no | only for clustering several nodes |

## Who runs it

cab shows no organisation of its own. To put yours in the footer, on
the sign-in page and on the account page (name, links, contact and
support addresses, in every language you translate), set
`config :cab, :operator, YourApp.CabOperator` to a module whose `info/0`
returns them; see `CabWeb.Operator`.

## License

MIT, see [LICENSE](LICENSE).
