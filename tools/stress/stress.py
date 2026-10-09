# /// script
# requires-python = ">=3.11"
# dependencies = ["websockets>=13", "httpx>=0.27"]
# ///
"""Stress test for cab against the running local stack (make up).

Drives one session the way a busy club night would, over real HTTP and
real LiveView websockets, and reports latency, errors, engine calls and
database pool waits per phase:

  A  viewers   N live viewers join the public session page
  B  signups   S members sign up, one per second; every viewer must see each one
  C  drags     T owner tabs place everyone into the allocator at once, then Start
  D  ballots   every room publishes a motion, then all ballots land at once
  E  links     a burst of short-link opens

    uv run tools/stress/stress.py [--viewers 300] [--signups 60] [--tabs 5]

Writes nothing outside the dev database it runs against; every run makes
its own users and club. Run `make fresh` afterwards for a clean demo.
"""

import argparse
import asyncio
import json
import os
import re
import statistics
import subprocess
import sys
import time
import urllib.parse

import httpx
import websockets

BASE = os.environ.get("BASE", "http://localhost:4000")
WS = BASE.replace("http", "ws", 1) + "/live/websocket"
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LOG = os.path.join(ROOT, ".run", "cab.log")
RUN = str(int(time.time()))

TARGETS = {  # phase -> (p95 seconds, max error count)
    "A": (1.0, 0),
    "B": (1.0, 0),
    "C": (0.3, 0),
    "D": (2.0, 0),
    "E": (0.2, 0),
}


def pct(values, p):
    if not values:
        return float("nan")
    values = sorted(values)
    return values[min(len(values) - 1, int(round(p / 100 * (len(values) - 1))))]


class LogWindow:
    """Counts engine calls and DB pool waits written to cab.log during a phase."""

    def __enter__(self):
        self.start = os.path.getsize(LOG) if os.path.exists(LOG) else 0
        return self

    def __exit__(self, *_exc):
        with open(LOG, "rb") as f:
            f.seek(self.start)
            text = f.read().decode("utf-8", "replace")
        self.engine = len(re.findall(r"^\[debug\] engine ", text, re.M))
        self.queues = [float(q) for q in re.findall(r"queue=([0-9.]+)ms", text)]


def csrf_of(html):
    m = re.search(r'name="csrf-token" content="([^"]+)"', html)
    return m and m.group(1)


async def user(client_kwargs, username):
    client = httpx.AsyncClient(base_url=BASE, **client_kwargs)
    r = await client.get("/dev/switch-user", params={"username": username})
    assert r.status_code == 302, f"switch-user {username}: {r.status_code}"
    return client


class LiveView:
    """One LiveView connection: join a page, collect diffs, push events."""

    def __init__(self, client, path):
        self.client, self.path = client, path
        self.diffs = []
        self.replies = {}
        self.ref = 0

    async def join(self):
        page = await self.client.get(self.path)
        html = page.text
        token = csrf_of(html)
        tag = re.search(r"<[^>]*data-phx-main[^>]*>", html).group(0)
        root = re.search(r'id="(phx-[^"]+)"', tag).group(1)
        session = re.search(r'data-phx-session="([^"]+)"', tag).group(1)
        static = re.search(r'data-phx-static="([^"]+)"', tag)
        cookie = "; ".join(f"{k}={v}" for k, v in self.client.cookies.items())
        query = urllib.parse.urlencode({"_csrf_token": token, "vsn": "2.0.0"})
        self.ws = await websockets.connect(f"{WS}?{query}", additional_headers={"cookie": cookie}, max_size=None)
        self.topic = f"lv:{root}"
        self.join_ref = "1"
        payload = {
            "url": BASE + self.path,
            "params": {"_csrf_token": token, "_mounts": 0},
            "session": session,
            "static": static.group(1) if static else None,
        }
        t0 = time.perf_counter()
        await self.ws.send(json.dumps([self.join_ref, self.join_ref, self.topic, "phx_join", payload]))
        while True:
            msg = json.loads(await self.ws.recv())
            if msg[3] == "phx_reply" and msg[1] == self.join_ref:
                assert msg[4]["status"] == "ok", msg[4]
                break
        self.joined_in = time.perf_counter() - t0
        self.reader = asyncio.create_task(self.read())
        self.beat = asyncio.create_task(self.heartbeat())

    async def read(self):
        try:
            async for raw in self.ws:
                msg = json.loads(raw)
                if msg[3] == "diff":
                    self.diffs.append(time.perf_counter())
                elif msg[3] == "phx_reply" and msg[1] in self.replies:
                    self.replies[msg[1]].set_result((time.perf_counter(), msg[4]))
        except websockets.ConnectionClosed:
            pass

    async def heartbeat(self):
        while True:
            await asyncio.sleep(20)
            await self.ws.send(json.dumps([None, "hb", "phoenix", "heartbeat", {}]))

    async def push(self, event, value, kind="hook"):
        self.ref += 1
        ref = f"e{self.ref}"
        fut = asyncio.get_running_loop().create_future()
        self.replies[ref] = fut
        t0 = time.perf_counter()
        await self.ws.send(json.dumps([self.join_ref, ref, self.topic, "event", {"type": kind, "event": event, "value": value}]))
        done, reply = await asyncio.wait_for(fut, 30)
        return done - t0, reply

    async def close(self):
        self.beat.cancel()
        await self.ws.close()


def report(name, label, latencies, errors, log, extra=""):
    p95_target, err_target = TARGETS[name]
    p50, p95, worst = pct(latencies, 50), pct(latencies, 95), max(latencies) if latencies else float("nan")
    ok = p95 <= p95_target and errors <= err_target
    queue = f"db wait p95 {pct(log.queues, 95):.1f}ms max {max(log.queues) if log.queues else 0:.1f}ms" if log.queues else "db wait n/a"
    print(f"{'PASS' if ok else 'FAIL'}  {name} {label:<34} p50 {p50*1000:7.0f}ms  p95 {p95*1000:7.0f}ms  max {worst*1000:7.0f}ms  "
          f"errors {errors}  engine calls {log.engine}  {queue}{extra}", flush=True)
    return ok


async def main(args):
    limits = httpx.Limits(max_connections=1000, max_keepalive_connections=200)
    kw = {"timeout": 60, "limits": limits}
    people = max(args.signups, args.rooms * 9)

    print(f"setup: club, head and {people} members (run {RUN})", flush=True)
    head = await user(kw, f"st-{RUN}-head")
    seed = subprocess.run(
        ["nix", "develop", "--command", "mix", "cab.seed_club", f"Stress {RUN}", "Kyiv", f"st-{RUN}-head"],
        cwd=os.path.join(ROOT, "platform"), capture_output=True, text=True)
    club = re.search(r"CLUB_UUID=(\S+)", seed.stdout).group(1)

    sem = asyncio.Semaphore(40)

    # first sign-in provisions the engine user (a password hash on the
    # engine side): paced, as real first sign-ins are
    async def member(i):
        async with sem:
            return await user(kw, f"st-{RUN}-m{i:03d}")

    members = await asyncio.gather(*[member(i) for i in range(people)])

    async def join_club(c, i):
        async with sem:
            r = await c.post(f"/api/v1/clubs/{club}/join-requests", json={"message": f"m{i}", "contact": f"@m{i}"})
            return r.json()["id"]

    ids = await asyncio.gather(*[join_club(c, i) for i, c in enumerate(members)])

    async def approve(i):
        async with sem:
            await head.patch(f"/api/v1/join-requests/{i}", json={"action": "approve"})

    await asyncio.gather(*[approve(i) for i in ids])
    r = await head.post(f"/api/v1/clubs/{club}/sessions", json={"name": f"Stress night {RUN}"})
    sess = r.json()["uuid"]
    page = f"/c/{club}/s/{sess}"
    results = []

    # A: viewers join
    print(f"A: {args.viewers} viewers join {page}", flush=True)
    with LogWindow() as log:
        viewers, errors = [], 0

        async def viewer():
            nonlocal errors
            async with sem:
                lv = LiveView(httpx.AsyncClient(base_url=BASE, **kw), page)
                try:
                    await lv.join()
                    viewers.append(lv)
                except Exception as e:  # noqa: BLE001
                    errors += 1
                    print("  join error:", repr(e)[:160])

        await asyncio.gather(*[viewer() for _ in range(args.viewers)])
    results.append(report("A", f"{args.viewers} viewers join", [v.joined_in for v in viewers], errors, log))

    # B: signups, one per second; each must reach every viewer
    print(f"B: {args.signups} signups, one per second, {len(viewers)} viewers watching", flush=True)
    with LogWindow() as log:
        fanout, errors, calls = [], 0, []
        for c in members[: args.signups]:
            before = [len(v.diffs) for v in viewers]
            t0 = time.perf_counter()
            r = await c.post(f"/api/v1/sessions/{sess}/signups", json={})
            calls.append(time.perf_counter() - t0)
            if r.status_code != 201:
                errors += 1
                continue
            deadline = time.perf_counter() + 10
            while time.perf_counter() < deadline and any(len(v.diffs) <= b for v, b in zip(viewers, before)):
                await asyncio.sleep(0.02)
            for v, b in zip(viewers, before):
                if len(v.diffs) > b:
                    fanout.append(v.diffs[b] - t0)
                else:
                    errors += 1
            await asyncio.sleep(max(0, 1 - (time.perf_counter() - t0)))
    results.append(report("B", "signup reaches every viewer", fanout, errors, log,
                          f"  (signup call p95 {pct(calls, 95)*1000:.0f}ms)"))

    # the rest sign up unmeasured, so the rooms can fill
    await asyncio.gather(*[c.post(f"/api/v1/sessions/{sess}/signups", json={}) for c in members[args.signups:]])
    state = (await head.get(f"/api/v1/sessions/{sess}")).json()
    pids = sorted(p["id"] for p in state["signups"])

    # C: owner tabs place everyone at once, then Start
    rooms = min(args.rooms, len(pids) // 9)
    slots = []
    for room in range(1, rooms + 1):
        slots += [f"{room}:{side}:{n}" for side in ("og", "oo", "cg", "co") for n in (1, 2)] + [f"{room}:judge"]
    plan = list(zip(pids, slots))
    print(f"C: {args.tabs} owner tabs place {len(plan)} people into {rooms} rooms, then Start", flush=True)
    with LogWindow() as log:
        tabs = []
        for _ in range(args.tabs):
            lv = LiveView(head, f"/c/{club}/owner/s/{sess}")
            await lv.join()
            tabs.append(lv)
        latencies, errors = [], 0

        async def place(tab, chunk):
            nonlocal errors
            for pid, slot in chunk:
                took, reply = await tab.push("place", {"id": pid, "slot": slot})
                latencies.append(took)
                if reply.get("status") != "ok":
                    errors += 1

        await asyncio.gather(*[place(t, plan[i:: args.tabs]) for i, t in enumerate(tabs)])
        t0 = time.perf_counter()
        _took, reply = await tabs[0].push("start", "", kind="form")
        start_took = time.perf_counter() - t0
        flash = json.dumps(reply)[:300]
        if "session started" not in flash:
            errors += 1
            print("  start did not report success:", flash)
    results.append(report("C", f"{len(plan)} drags from {args.tabs} tabs", latencies, errors, log,
                          f"  (Start, {rooms} rooms created: {start_took*1000:.0f}ms)"))
    for t in tabs:
        await t.close()

    # D: motions, then all ballots at once
    state = (await head.get(f"/api/v1/sessions/{sess}")).json()
    room_list = state["rooms"]
    print(f"D: {len(room_list)} motions, then {len(room_list)} ballots at once", flush=True)
    with LogWindow() as log:
        errors, latencies = 0, []

        async def motion(room):
            r = await head.post(f"/api/v1/rooms/{room['id']}/motion", json={"session_uuid": sess, "motion_text": f"THW stress {room['id']}"})
            return r.status_code

        codes = await asyncio.gather(*[motion(r) for r in room_list])
        errors += sum(1 for c in codes if c != 200)
        state = (await head.get(f"/api/v1/sessions/{sess}")).json()

        def scores(room):
            out = []
            for team in sorted(room["RoomTeams"], key=lambda t: t["position"]):
                ids = [s["EventParticipant"]["id"] for s in team["RoomSpeakers"]]
                base = {1: 80, 2: 77, 3: 74, 4: 71}[team["position"]]
                out.append({"position": team["position"], "speaker_participant_id": ids[0], "iron": False, "score": base})
                out.append({"position": team["position"], "speaker_participant_id": ids[-1], "iron": ids[0] == ids[-1], "score": base - 1})
            return out

        async def ballot(room):
            nonlocal errors
            t0 = time.perf_counter()
            r = await head.post(f"/api/v1/rooms/{room['id']}/ballot", json={"session_uuid": sess, "scores": scores(room)})
            latencies.append(time.perf_counter() - t0)
            if r.status_code != 200:
                errors += 1
                print("  ballot error:", r.status_code, r.text[:160])

        before = [len(v.diffs) for v in viewers]
        await asyncio.gather(*[ballot(r) for r in state["rooms"]])
        await asyncio.sleep(3)
        missed = sum(1 for v, b in zip(viewers, before) if len(v.diffs) <= b)
    results.append(report("D", f"{len(room_list)} ballots at once", latencies, errors + missed, log,
                          f"  (viewers that missed the update: {missed})"))

    # E: short links
    code = (await head.get(page)).text
    short = re.search(r'data-copy="https?://[^/"]+/([a-z2-9]{6})"', code).group(1)
    paths = [f"/{short}", f"/{short}/1", f"/{short}/{rooms}"] * (args.links // 3)
    print(f"E: {len(paths)} short-link opens, 50 at a time", flush=True)
    with LogWindow() as log:
        latencies, errors = [], 0
        anon = httpx.AsyncClient(base_url=BASE, **kw)
        lsem = asyncio.Semaphore(50)

        async def open_link(p):
            nonlocal errors
            async with lsem:
                t0 = time.perf_counter()
                r = await anon.get(p)
                latencies.append(time.perf_counter() - t0)
                if r.status_code != 302:
                    errors += 1

        await asyncio.gather(*[open_link(p) for p in paths])
    results.append(report("E", f"{len(paths)} short-link opens", latencies, errors, log))

    for v in viewers:
        await v.close()
    print("ALL TARGETS MET" if all(results) else "SOME TARGETS MISSED", flush=True)
    return 0 if all(results) else 1


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--viewers", type=int, default=300)
    ap.add_argument("--signups", type=int, default=60)
    ap.add_argument("--rooms", type=int, default=20)
    ap.add_argument("--tabs", type=int, default=5)
    ap.add_argument("--links", type=int, default=600)
    sys.exit(asyncio.run(main(ap.parse_args())))
