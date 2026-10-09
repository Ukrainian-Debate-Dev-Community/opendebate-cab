# Stress test

    make up && make stress        # or: uv run tools/stress/stress.py --viewers 300

Drives one session over real HTTP and real LiveView websockets against
the running dev stack: 300 viewers join, 60 sign-ups arrive one per
second, 5 owner tabs place 180 people into 20 rooms and start, 20
ballots land at once, then a burst of short-link opens. Each phase
reports p50/p95/max latency, errors, engine calls and database pool
waits (counted from the dev log).

## Results, 9 Oct 2026 (laptop, dev server, local engine)

| Phase | Load | p95 | Target | Engine calls |
|---|---|---|---|---|
| A viewers join | 300 at once | 204 ms | 1 s | 8 per viewer |
| B sign-up reaches every viewer | 60, one per second, 300 watching | 445 ms | 1 s | ~9 per sign-up |
| C drags | 180 from 5 tabs, then Start (20 rooms) | 176 ms | 300 ms | ~4.5 per drag |
| D ballots | 20 at once | 1.67 s | 2 s | 108 in total |
| E short-link opens | 600, 50 at a time | 2.8 s dev, 7 ms prod | 200 ms | 0 |

E misses in dev only: the dev code reloader serves requests one at a
time, so dev latency under concurrency measures the reloader. A local
production build served the same short links at ~9,000 requests a
second with p95 7 ms (ApacheBench, 50 concurrent).

## What the runs changed

- Every open page used to re-read the session from the engine on each
  change (about 1,200 engine reads per sign-up at 300 viewers). The
  writer now reads once and pushes the state; a burst of changes
  shares one or two reads.
- Two owner tabs dragging at once lost placements (lost update); draft
  edits now run under a row lock.
- A drained HTTP pool to the engine answered 500; it is now an engine
  error reported in words.
- Room short links resolve from room ids recorded at creation, with no
  engine call.

## Where the limit is

The engine (one Node process) queues reads under concurrency: 35-80 ms
at rest, up to ~1.5 s at p95 during the bursts above. cab's own work
stays in single-digit milliseconds of database time.
