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
make setup     # engine checkout and packages, Elixir deps, databases
make dev:up    # engine on :3100, cab on :4000 (make dev does the same)
make test      # unit tests
make test-all  # everything that runs without the stack
```

The standard targets (`setup build test test-all lint fmt clean`) are
local and never need the running stack. Targets named `dev:<x>` work on
the local stack:

| Command | Does |
|---|---|
| `make dev:up` / `make dev:down` / `make dev:restart` | start, stop, restart the engine and cab |
| `make dev:status` / `make dev:logs` | what is running / follow the logs in `.run/` |
| `make dev:fresh DEV_USER=<your cab username>` | wipe both databases, load demo data |
| `make dev:e2e` | the full session walkthrough against the running stack |
| `make dev:phone DEV_USER=<username>` | every key page as an iPhone 15 |
| `make dev:stress` | load test against the running stack |
| `make dev:backfill` | record lifecycle facts on older session rows |
| `make dev:bump-engine` | move the engine pin to the engine's latest release (`REF=<ref>` for another) |
| `make dev:api-docs` | refresh the engine's API description from the pinned engine |
| `make dev:image` | build the release image locally (Docker needed) |

The dev stack reads `.env` at the repo root (OAuth keys, engine secret,
`LEGAL_DIR`) and `engine/.env`. Tooling comes from `nix develop`.

## Branches and releases

- `nightly` is the default branch and the only target for pull requests
  (squash-merged); CI (`test`, `lint`, `guard`, `docker`) must pass.
  Every night a workflow moves the engine pin to the engine's latest
  release tag and opens a pull request into `nightly` when it changed.
- `main` moves only on a release, by fast-forward to the release commit.
- Versions are the git tags `vX.Y.Z`. A release, from a clean `nightly`
  equal to `origin/nightly` whose CI is green:

  ```sh
  make release BUMP=patch|minor|major   # or VERSION=X.Y.Z
  make release BUMP=patch DRY_RUN=1     # preview the version and notes
  ```

  It shows the next version and the release notes (from the squash-merged
  pull request titles since the last tag) and asks you to type
  `opendebate-cab:vX.Y.Z`. Then it writes the version into the `mix.exs`
  files, prepends the notes to `CHANGELOG.md`, commits
  `chore(release): opendebate-cab vX.Y.Z` on `nightly` and pushes it,
  waits for CI on that commit, fast-forwards `main` to it, pushes the
  annotated tag and publishes the GitHub release. If a step fails after
  the commit, `make release RESUME=1` finishes it. The tag publishes the
  image `ghcr.io/ukrainian-debate-dev-community/opendebate-cab:vX.Y.Z`
  (and `:sha-<commit>`).
- `make dev:image` builds the image locally (Docker needed).

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
| `RETURN_HOSTS` | no | e.g. `example.org,www.example.org`: sibling sites a sign-in may send people back to (`/signin?return_to=https://example.org/...`) |
| `SHORT_LINK_HOSTS` | no | e.g. `example.org,www.example.org`: hosts besides cab's own that short links may point to |
| `DEFAULT_PHONE_COUNTRY` | no | e.g. `UA`: phone numbers typed without a `+code` are read in this country, and the phone field opens on it; unset, the field opens on the visitor's own region and the server asks for a `+code` |
| `RATE_LIMIT_ENABLED` | no | the JSON API's rate limit, `true` by default |
| `RATE_LIMIT_SIGNED_IN`, `RATE_LIMIT_ANONYMOUS` | no | requests per minute, 60 and 20 by default |
| `FORM_RATE_LIMIT` | no | `true` turns on the public forms' rate limit (off by default, independent of `RATE_LIMIT_ENABLED`) |
| `TURNSTILE_SITE_KEY`, `TURNSTILE_SECRET_KEY` | no | Cloudflare Turnstile on the public forms; off unless both are set |
| `PHX_SERVER` | set by the image | starts the web server |
| `PORT` | no | 4000 by default |
| `POOL_SIZE` | no | the database pool, 10 by default |
| `ECTO_IPV6` | no | `true` to reach the database over IPv6 |
| `DNS_CLUSTER_QUERY` | no | only for clustering several nodes |

**Contact fields on other sites.** A site that renders cab's form
blocks (`:phone`, `:email`, `:telegram`) on its own pages gets the
typing helpers (the phone's country picker and spacing, the checks
when a field is left) by loading cab's standalone script:
`<script defer src="https://<cab host>/assets/js/contact-fields.js"></script>`.
The messages come from the blocks' `data-msg-*` attributes, in the
page's language.

## Bot protection

The public forms - a guest's registration at `/r/<session>` and a club
join request at `/c/<club>/join` - can be guarded (`CabWeb.BotGuard`).
Both protections are off until an operator turns them on; signed-in
members registering for a session are never asked.

- **Rate limits** (`FORM_RATE_LIMIT=true`, or `rate_limit: true` in
  `config :cab, CabWeb.BotGuard`): per client IP 30 guest registrations
  per 10 minutes (room for a club registering over one Wi-Fi), per
  session 120 per hour; join requests 10 per hour per account and 30
  per hour per IP. Over a limit the form answers 429 with `Retry-After`.
  Behind Cloudflare the client IP is `CF-Connecting-IP`. The numbers
  live in the same config.
- **Cloudflare Turnstile**, when `TURNSTILE_SITE_KEY` and
  `TURNSTILE_SECRET_KEY` are set: the widget on the form, its token
  checked with Cloudflare on submit. If Cloudflare cannot be reached the
  submit is refused with a "try again" message.

To get the keys: in the Cloudflare dashboard open Turnstile, choose
**Add widget**, name it, add cab's hostname (e.g. `cab.example.org`),
pick **Managed** mode and create it; copy the site key and the secret
key into the two variables. Cloudflare's test keys
(`1x00000000000000000000AA` with the secret
`1x0000000000000000000000000000000AA`) always pass, for local trials.

E-mail answers are checked by `Core.Forms.email?/1`: no spaces, control
or percent characters, quotes, misplaced dots, a real top-level domain
and 254 characters at most.

## Who runs it

cab shows no organisation of its own. To put yours in the footer, on
the sign-in page and on the account page (name, links, contact and
support addresses, in every language you translate), set
`config :cab, :operator, YourApp.CabOperator` to a module whose `info/0`
returns them; see `CabWeb.Operator`.

## License

MIT, see [LICENSE](LICENSE).
