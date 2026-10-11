# opendebate

The OpenDebate platform, an Elixir umbrella:

- `apps/core`: the engine client and the shared mailer
- `apps/cab`: debate clubs and their sessions (cab.uadebate.com)
- `apps/dfu`: the NGO cabinet (skeleton)
- `apps/uadebate`: the public site (skeleton)

Dependencies point down only: uadebate -> dfu -> cab -> core. cab knows
nothing above it.

`engine/` is the debate engine, [opendebate-engine](https://github.com/Ukrainian-Debate-Dev-Community/opendebate-engine),
pinned as a git submodule. Policy and Terms are deployment documents:
in development they are read from the `opendebate-server` checkout next
to this repo, in production from `LEGAL_DIR`.

## Getting started

```sh
make setup   # engine checkout and packages, Elixir deps, databases
make up      # engine on :3100, cab on :4000
make test    # unit tests
make test-all
```

The dev stack reads `.env` at the repo root (OAuth keys, engine secret)
and `engine/.env`.

## License

MIT, see [LICENSE](LICENSE).
