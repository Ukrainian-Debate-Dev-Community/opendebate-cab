# opendebate

The OpenDebate platform, an Elixir umbrella:

- `apps/core`: the engine client and the shared mailer
- `apps/cab`: debate clubs and their sessions (cab.uadebate.com)
- `apps/dfu`: the NGO cabinet (skeleton)
- `apps/uadebate`: the public site, uadebate.com (its own database for
  news, events and editors; clubs and accounts read from cab)

Dependencies point down only: uadebate -> dfu -> cab -> core. cab knows
nothing above it.

`engine/` is the debate engine, [opendebate-engine](https://github.com/Ukrainian-Debate-Dev-Community/opendebate-engine),
pinned as a git submodule. Policy and Terms are deployment documents:
in development they are read from the `opendebate-server` checkout next
to this repo, in production from `LEGAL_DIR`.

## Getting started

```sh
make setup   # engine checkout and packages, Elixir deps, databases
make up      # engine on :3100, cab on :4000, uadebate.com on :4001
make test    # unit tests
make test-all
make test-phone  # every key page as an iPhone 15, against the running stack (make up)
```

The dev stack reads `.env` at the repo root (OAuth keys, engine secret)
and `engine/.env`.

## uadebate.com

Public pages never read a session: they are the same for everyone.
Editors open `/manage` (the link is given, not shown anywhere) after
signing in on cab; it is a 404 for anyone without the content-manager
role. cab admins grant the role on `/manage/people`; for the first
setup, `mix uadebate.grant <username-or-email>`.

Production settings (besides cab's): `UADEBATE_DATABASE_URL`,
`UADEBATE_HOST`, `UADEBATE_PORT` (default 4001), `CAB_URL` (where the
Cabinet links point), and on cab `SESSION_COOKIE_DOMAIN` (for example
`.uadebate.com`) so the sign-in is shared. Both endpoints start with
`PHX_SERVER=true` and sign their cookies with `SECRET_KEY_BASE`.

## Branches and releases

- `nightly` is the default branch and the only target for pull requests;
  CI (`test`, `lint`, `guard`, `docker`) must pass. Every night a workflow
  moves the engine pin to the engine's latest main and opens a pull
  request into `nightly` when it changed.
- `master` moves only on a release: `make release VERSION=vX.Y.Z` from a
  clean `nightly` whose CI is green fast-forwards `master`, tags the
  commit and pushes both. The tag publishes the image
  `ghcr.io/ukrainian-debate-dev-community/opendebate:vX.Y.Z` (and
  `:sha-<commit>`) with a GitHub release; opendebate-server deploys it.
- `make image` builds the image locally (Docker needed).

The image runs the `full` release (cab on 4000, uadebate.com on 4001) and
answers `GET /healthz` on both ports. Before starting a new version run the
migrations:

```sh
bin/full eval "Cab.Release.migrate()"
bin/full eval "Uadebate.Release.migrate()"
```

## Production settings

| Variable | Needed | What |
|---|---|---|
| `DATABASE_URL` | yes | cab's database, `ecto://user:pass@host/db` |
| `UADEBATE_DATABASE_URL` | yes | uadebate.com's database |
| `SECRET_KEY_BASE` | yes | signs cookies; both sites use the same one |
| `PHX_HOST` | yes | cab's host, e.g. `cab.uadebate.com` |
| `UADEBATE_HOST` | yes | the public site's host, e.g. `uadebate.com` |
| `ENGINE_URL` | yes | the engine, e.g. `http://engine:3000` |
| `ENGINE_JWT_SECRET` | yes | shared with the engine's `JWT_SECRET`; the dev default is refused |
| `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET` | yes | sign-in with GitHub |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` | yes | sign-in with Google |
| `SESSION_COOKIE_DOMAIN` | for sharing | e.g. `.uadebate.com`, so uadebate.com/manage sees the cab sign-in |
| `UADEBATE_UPLOADS_DIR` | yes | folder for news cover images, served at `/uploads`; a persistent volume, kept in the backups |
| `CAB_URL` | no | cab's address as uadebate.com links it; defaults to `https://$PHX_HOST` |
| `LEGAL_DIR` | yes | folder with `en/policy.md`, `en/terms.md` (and other languages); 404 without |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD` | for mail | without `SMTP_HOST` mail is kept in memory and not sent |
| `MAIL_FROM` | for mail | `Name <address>`, e.g. `cab <noreply@uadebate.com>` |
| `PHX_SERVER` | set by the image | starts the web servers |
| `PORT`, `UADEBATE_PORT` | no | 4000 and 4001 by default |
| `POOL_SIZE`, `UADEBATE_POOL_SIZE` | no | database pools, 10 and 5 by default |
| `DNS_CLUSTER_QUERY` | no | only for clustering several nodes |

## License

MIT, see [LICENSE](LICENSE).
