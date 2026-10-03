#!/usr/bin/env bash
# M1 acceptance: curl through the ENTIRE club lifecycle REST flow
# against the live stack (engine :3100 + gateway :4000 — `make up`,
# dev DB migrated). Every step asserts the HTTP status and a JSON
# field. Exits non-zero on the first failed assertion.
#
#   platform/apps/cab/priv/walkthrough_rest.sh
#
# Cast: 1 head + 8 speakers + 1 judge (BP rooms hold 4 teams x 2
# speakers, so pairing needs speakers in multiples of 8). Identities
# are /dev/switch-user cookie jars; the club is seeded via
# `mix cab.seed_club`.

set -u
BASE="${BASE:-http://localhost:4000}"
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
RUN="$(date +%s)"
JARS="$(mktemp -d)"
BODY="$JARS/body.json"
STEP=0

say()  { printf '\n== %s\n' "$*"; }
fail() { printf 'FAIL: %s\nlast body: %s\n' "$*" "$(cat "$BODY" 2>/dev/null)"; exit 1; }

# req <jar> <method> <path> [json-body] -> status in $STATUS, body in $BODY
req() {
  jar="$1"; method="$2"; path="$3"; data="${4:-}"
  if [ -n "$data" ]; then
    STATUS=$(curl -s -o "$BODY" -w '%{http_code}' -b "$JARS/$jar" -X "$method" \
      -H 'content-type: application/json' -d "$data" "$BASE$path")
  else
    STATUS=$(curl -s -o "$BODY" -w '%{http_code}' -b "$JARS/$jar" -X "$method" "$BASE$path")
  fi
}

# assert <jar> <method> <path> <expected-status> <jq-expr> <expected-value> [json-body]
assert() {
  jar="$1"; method="$2"; path="$3"; want_status="$4"; expr="$5"; want="$6"; data="${7:-}"
  STEP=$((STEP + 1))
  req "$jar" "$method" "$path" "$data"
  [ "$STATUS" = "$want_status" ] || fail "[$STEP] $method $path: status $STATUS, want $want_status"
  got=$(jq -r "$expr" "$BODY" 2>/dev/null) || fail "[$STEP] $method $path: body is not JSON"
  [ "$got" = "$want" ] || fail "[$STEP] $method $path: $expr = '$got', want '$want'"
  printf 'ok %2d  %-5s %-55s %s  %s=%s\n' "$STEP" "$method" "$path" "$STATUS" "$expr" "$got"
}

command -v jq >/dev/null || { echo "jq is required"; exit 1; }
curl -sf -o /dev/null --max-time 3 "$BASE/" || { echo "gateway not up — run: make up"; exit 1; }

# ----------------------------------------------------------------
say "users via /dev/switch-user (cookie jar = identity)"
# ----------------------------------------------------------------
USERS="head j1 s1 s2 s3 s4 s5 s6 s7 s8"
for u in $USERS; do
  code=$(curl -s -o /dev/null -w '%{http_code}' -c "$JARS/$u" \
    "$BASE/dev/switch-user?username=wt-$RUN-$u")
  [ "$code" = "302" ] || fail "switch-user $u: status $code, want 302"
done
echo "ok     10 users signed in (wt-$RUN-*)"

# ----------------------------------------------------------------
say "seed club via mix task (club creation is NOT in the API)"
# ----------------------------------------------------------------
SEED_OUT=$(cd "$ROOT/platform" && nix develop --command sh -c \
  "mix cab.seed_club 'BP Walkthrough $RUN' 'Kyiv' 'wt-$RUN-head'" 2>&1) \
  || { echo "$SEED_OUT"; fail "mix cab.seed_club failed"; }
CLUB=$(printf '%s\n' "$SEED_OUT" | sed -n 's/^CLUB_UUID=//p' | tail -1)
[ -n "$CLUB" ] || { echo "$SEED_OUT"; fail "no CLUB_UUID in seed output"; }
echo "club: $CLUB"

assert head GET "/api/v1/clubs/$CLUB" 200 '.name' "BP Walkthrough $RUN"

# ----------------------------------------------------------------
say "join requests (a join request IS a pending membership)"
# ----------------------------------------------------------------
REQ_IDS=""
for u in j1 s1 s2 s3 s4 s5 s6 s7 s8; do
  assert "$u" POST "/api/v1/clubs/$CLUB/join-requests" 201 '.status' pending
  REQ_IDS="$REQ_IDS $u:$(jq -r '.id' "$BODY")"
done

say "role trees: a non-member/member never reaches the owner tree"
assert s1 GET "/api/v1/clubs/$CLUB/members" 403 '.error' forbidden
req s1 GET "/c/$CLUB/owner"
[ "$STATUS" = "403" ] || fail "GET /c/$CLUB/owner as pending s1: status $STATUS, want 403"
echo "ok     /c/.../owner as pending user -> 403"

say "head approves everyone"
for pair in $REQ_IDS; do
  id="${pair#*:}"
  assert head PATCH "/api/v1/join-requests/$id" 200 '.status' approved '{"action":"approve"}'
done

req s1 GET "/c/$CLUB/owner"
[ "$STATUS" = "403" ] || fail "GET /c/$CLUB/owner as approved member: status $STATUS, want 403"
echo "ok     /c/.../owner as approved member -> still 403"
assert s1 GET "/api/v1/clubs/$CLUB/members" 200 '.members | length' 10

# ----------------------------------------------------------------
say "head opens a session"
# ----------------------------------------------------------------
assert s1 POST "/api/v1/clubs/$CLUB/sessions" 403 '.error' forbidden '{"name":"nope"}'
assert head POST "/api/v1/clubs/$CLUB/sessions" 201 '.uuid | length' 36 \
  "{\"name\":\"Walkthrough night $RUN\"}"
SESSION=$(jq -r '.uuid' "$BODY")
assert s1 GET "/api/v1/sessions/$SESSION" 200 '.stage' signup

# ----------------------------------------------------------------
say "signups: 8 speakers + 1 judge"
# ----------------------------------------------------------------
for u in s1 s2 s3 s4 s5 s6 s7 s8; do
  assert "$u" POST "/api/v1/sessions/$SESSION/signups" 201 '.role' speaker '{"as":"speak"}'
done
assert j1 POST "/api/v1/sessions/$SESSION/signups" 201 '.role' adjudicator '{"as":"judge"}'

# ----------------------------------------------------------------
say "head makes rooms from attendance"
# ----------------------------------------------------------------
assert head POST "/api/v1/sessions/$SESSION/rooms" 201 '.rooms_created' 1
assert j1 GET "/api/v1/sessions/$SESSION" 200 '.stage' running
ROOM=$(jq -r '.rooms[0].id' "$BODY")
WINNER_RT=$(jq -r '.rooms[0].RoomTeams | sort_by(.position) | .[1].id' "$BODY")
WINNER_NAME=$(jq -r ".rooms[0].RoomTeams[] | select(.id == $WINNER_RT) | .Team.name" "$BODY")
echo "room: $ROOM, picked winner room_team: $WINNER_RT ($WINNER_NAME)"

# ----------------------------------------------------------------
say "the judge posts the motion, then the winner"
# ----------------------------------------------------------------
assert j1 POST "/api/v1/rooms/$ROOM/motion" 200 '.motion.motion_text' \
  "THW walk through REST $RUN" \
  "{\"session_uuid\":\"$SESSION\",\"motion_text\":\"THW walk through REST $RUN\"}"
assert j1 POST "/api/v1/rooms/$ROOM/winner" 200 '.status' confirmed \
  "{\"session_uuid\":\"$SESSION\",\"room_team_id\":$WINNER_RT}"

# ----------------------------------------------------------------
say "head finishes; history shows the winner"
# ----------------------------------------------------------------
assert head POST "/api/v1/sessions/$SESSION/finish" 200 '.status' completed
assert j1 GET "/api/v1/sessions/$SESSION" 200 '.stage' done
assert head GET "/api/v1/clubs/$CLUB" 200 '.history[0].winner' "$WINNER_NAME"

printf '\nWALKTHROUGH GREEN: %s steps, club %s\n' "$STEP" "$CLUB"
