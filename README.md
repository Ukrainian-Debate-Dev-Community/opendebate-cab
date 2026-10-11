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

## License

MIT, see [LICENSE](LICENSE).
