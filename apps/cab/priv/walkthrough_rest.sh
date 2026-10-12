#!/usr/bin/env bash
# The full session roundtrip against the live stack (engine :3100 +
# cab :4000; `make fresh` for a clean database, then `make test-e2e`).
# Every step asserts the HTTP status and a JSON field or page marker;
# exits non-zero on the first failed assertion.
#
# Covers: club seeding, join requests and approval, opening a session,
# role-less sign-ups, closing, composing rooms (the seat decides who
# adjudicates), rebuilding them, motions with the prep clock, ballots with
# the tie gate and head-only edits of a confirmed ballot, an iron
# team, waitlist-only removal, finishing with the recorded winner,
# standings, My page, guests via the shared URL and personal links (a
# guest judge fills the ballot, a removed guest's link dies), privacy
# walls, club profile edits and member removal.
#
# Identities are /dev/switch-user cookie jars; the club is seeded via
# `mix cab.seed_club`. Safe to re-run: every run makes its own users.

set -u
BASE="${BASE:-http://localhost:4000}"
# where `mix` runs; a project that holds cab as a submodule sets
# MIX_ROOT to itself so its own build is used
ROOT="${MIX_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
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

# reqc <jar> <method> <path> - like req, but WRITES cookies back to
# the jar (the guest HTML flows are session+csrf browser forms)
reqc() {
  jar="$1"; method="$2"; path="$3"
  STATUS=$(curl -s -o "$BODY" -w '%{http_code}' -b "$JARS/$jar" -c "$JARS/$jar" \
    -X "$method" "$BASE$path")
}

# the csrf token of the last-fetched HTML page (any form's token of
# the same browser session validates)
csrf() {
  { sed -n 's/.*name="_csrf_token" value="\([^"]*\)".*/\1/p' "$BODY"
    sed -n 's/.*name="csrf-token" content="\([^"]*\)".*/\1/p' "$BODY"; } | head -1
}

# html_ok <label> - count a non-JSON step after manual checks passed
html_ok() {
  STEP=$((STEP + 1))
  printf 'ok %2d  %-5s %-55s %s  %s\n' "$STEP" "$2" "$3" "$4" "$1"
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
curl -sf -o /dev/null --max-time 3 "$BASE/" || { echo "gateway not up; run: make up"; exit 1; }

# ----------------------------------------------------------------
say "users via /dev/switch-user (cookie jar = identity)"
# ----------------------------------------------------------------
USERS="head j1 s1 s2 s3 s4 s5 s6 s7 s8 x1"
for u in $USERS; do
  code=$(curl -s -o /dev/null -w '%{http_code}' -c "$JARS/$u" \
    "$BASE/dev/switch-user?username=wt-$RUN-$u")
  [ "$code" = "302" ] || fail "switch-user $u: status $code, want 302"
done
echo "ok     11 users signed in (wt-$RUN-*)"

# ----------------------------------------------------------------
say "seed club via mix task (club creation is NOT in the API)"
# ----------------------------------------------------------------
SEED_OUT=$(cd "$ROOT" && nix develop --command sh -c \
  "mix cab.seed_club 'BP Walkthrough $RUN' 'Kyiv' 'wt-$RUN-head'" 2>&1) \
  || { echo "$SEED_OUT"; fail "mix cab.seed_club failed"; }
CLUB=$(printf '%s\n' "$SEED_OUT" | sed -n 's/^CLUB_UUID=//p' | tail -1)
[ -n "$CLUB" ] || { echo "$SEED_OUT"; fail "no CLUB_UUID in seed output"; }
echo "club: $CLUB"

assert head GET "/api/cab/v1/clubs/$CLUB" 200 '.name' "BP Walkthrough $RUN"

# ----------------------------------------------------------------
say "join requests (a join request IS a pending membership + the two REQUIRED answers)"
# ----------------------------------------------------------------
# a bare request (no message/contact) is rejected - never a bare button
assert j1 POST "/api/cab/v1/clubs/$CLUB/join-requests" 422 '.details.message | length' 1
REQ_IDS=""
for u in j1 s1 s2 s3 s4 s5 s6 s7 s8; do
  assert "$u" POST "/api/cab/v1/clubs/$CLUB/join-requests" 201 '.status' pending \
    "{\"message\":\"I am wt-$RUN-$u and I debate\",\"contact\":\"@wt-$u\"}"
  REQ_IDS="$REQ_IDS $u:$(jq -r '.id' "$BODY")"
done
# the answers are stored on the request
assert j1 GET "/api/cab/v1/clubs/$CLUB" 200 '.uuid' "$CLUB"

say "role trees: a non-member/member never reaches the owner tree"
# a public club's roster is public; the owner tree never is
assert s1 GET "/api/cab/v1/clubs/$CLUB/members" 200 '.members | length' 1
req s1 GET "/c/$CLUB/owner"
[ "$STATUS" = "403" ] || fail "GET /c/$CLUB/owner as pending s1: status $STATUS, want 403"
echo "ok     /c/.../owner as pending user -> 403"

say "head approves everyone"
for pair in $REQ_IDS; do
  id="${pair#*:}"
  assert head PATCH "/api/cab/v1/join-requests/$id" 200 '.status' approved '{"action":"approve"}'
done

req s1 GET "/c/$CLUB/owner"
[ "$STATUS" = "403" ] || fail "GET /c/$CLUB/owner as approved member: status $STATUS, want 403"
echo "ok     /c/.../owner as approved member -> still 403"
assert s1 GET "/api/cab/v1/clubs/$CLUB/members" 200 '.members | length' 10

# ----------------------------------------------------------------
say "head opens a session"
# ----------------------------------------------------------------
assert s1 POST "/api/cab/v1/clubs/$CLUB/sessions" 403 '.error' forbidden '{"name":"nope"}'
assert head POST "/api/cab/v1/clubs/$CLUB/sessions" 201 '.uuid | length' 36 \
  "{\"name\":\"Walkthrough night $RUN\",\"date\":\"2026-10-09\",\"time\":\"18:30\"}"
SESSION=$(jq -r '.uuid' "$BODY")
assert s1 GET "/api/cab/v1/sessions/$SESSION" 200 '.stage' signup
assert s1 GET "/api/cab/v1/sessions/$SESSION" 200 '.scheduled_at' "2026-10-09T18:30:00Z"

# ----------------------------------------------------------------
say "signups: 8 speakers + 1 judge"
# ----------------------------------------------------------------
for u in s1 s2 s3 s4 s5 s6 s7 s8; do
  assert "$u" POST "/api/cab/v1/sessions/$SESSION/signups" 201 '.participant_id | type' number '{}'
done
assert j1 POST "/api/cab/v1/sessions/$SESSION/signups" 201 '.participant_id | type' number '{}'

# ----------------------------------------------------------------
say "signups on behalf + removal (head full control)"
# ----------------------------------------------------------------
assert x1 POST "/api/cab/v1/clubs/$CLUB/join-requests" 201 '.status' pending \
  '{"message":"extra member","contact":"@x1"}'
X1_REQ=$(jq -r '.id' "$BODY")
assert head PATCH "/api/cab/v1/join-requests/$X1_REQ" 200 '.status' approved '{"action":"approve"}'

# only the head signs up others; the head may remove anyone
assert s1 POST "/api/cab/v1/sessions/$SESSION/signups" 403 '.error' forbidden \
  "{\"username\":\"wt-$RUN-x1\"}"
assert head POST "/api/cab/v1/sessions/$SESSION/signups" 201 '.username' "wt-$RUN-x1" \
  "{\"username\":\"wt-$RUN-x1\"}"
X1_PID=$(jq -r '.participant_id' "$BODY")
assert s1 DELETE "/api/cab/v1/sessions/$SESSION/signups/$X1_PID" 403 '.error' forbidden
assert head DELETE "/api/cab/v1/sessions/$SESSION/signups/$X1_PID" 200 '.status' removed

# self-removal: s8 steps out and back in
assert s8 GET "/api/cab/v1/sessions/$SESSION" 200 '.stage' signup
S8_PID=$(jq -r --arg name "wt-$RUN-s8" \
  '.signups[] | select(.name == $name) | .id' "$BODY")
assert s8 DELETE "/api/cab/v1/sessions/$SESSION/signups/$S8_PID" 200 '.status' removed
assert s8 POST "/api/cab/v1/sessions/$SESSION/signups" 201 '.participant_id | type' number '{}'

# ----------------------------------------------------------------
say "the close-signups gate (rooms are made after registration closes)"
# ----------------------------------------------------------------
# no rooms while sign-ups are open (and never without a spec)
assert head POST "/api/cab/v1/sessions/$SESSION/rooms" 422 \
  '.details.rooms | contains("nothing is allocated automatically")' true
assert head POST "/api/cab/v1/sessions/$SESSION/reopen-signups" 409 \
  '.error | contains("while it is closed")' true

say "head closes sign-ups (member cannot)"
assert s1 POST "/api/cab/v1/sessions/$SESSION/close-signups" 403 '.error' forbidden
assert head POST "/api/cab/v1/sessions/$SESSION/close-signups" 200 '.stage' closed
assert head GET "/api/cab/v1/sessions/$SESSION" 200 '.stage' closed

say "signups after close -> 409; closing twice -> 409"
assert x1 POST "/api/cab/v1/sessions/$SESSION/signups" 409 \
  '.error | contains("Registration is not open")' true '{}'
assert head POST "/api/cab/v1/sessions/$SESSION/close-signups" 409 \
  '.error | contains("only be closed while it is open")' true

say "reopen, sign-ups live again, re-close"
assert head POST "/api/cab/v1/sessions/$SESSION/reopen-signups" 200 '.stage' signup
assert head GET "/api/cab/v1/sessions/$SESSION" 200 '.stage' signup
assert head POST "/api/cab/v1/sessions/$SESSION/close-signups" 200 '.stage' closed

# ----------------------------------------------------------------
say "explicit composition (the head places everyone), rebuild"
# ----------------------------------------------------------------
assert head GET "/api/cab/v1/sessions/$SESSION" 200 '.stage' closed
# registration carries no role: the head decides j1 chairs, s1-s8 speak
COMPOSE=$(jq -c '{rooms: [{
  adjudicator_participant_id: ([.signups[] | select(.name | endswith("-j1")) | .id][0]),
  teams: ([.signups[] | select(.name | test("-s[1-8]$")) | .id][0:8]
          | [.[0:2], .[2:4], .[4:6], .[6:8]])}]}' "$BODY")

assert s1 POST "/api/cab/v1/sessions/$SESSION/rooms" 403 '.error' forbidden "$COMPOSE"
assert head POST "/api/cab/v1/sessions/$SESSION/rooms" 201 '.rooms_created' 1 "$COMPOSE"
assert head GET "/api/cab/v1/sessions/$SESSION" 200 '.stage' running

say "rooms rebuild: delete pending rooms, session back to :closed"
assert s1 DELETE "/api/cab/v1/sessions/$SESSION/rooms" 403 '.error' forbidden
assert head DELETE "/api/cab/v1/sessions/$SESSION/rooms" 200 '.rooms_deleted' 1
assert head GET "/api/cab/v1/sessions/$SESSION" 200 '.stage' closed

# ----------------------------------------------------------------
say "head composes the rooms again"
# ----------------------------------------------------------------
assert head POST "/api/cab/v1/sessions/$SESSION/rooms" 201 '.rooms_created' 1 "$COMPOSE"
assert j1 GET "/api/cab/v1/sessions/$SESSION" 200 '.stage' running
ROOM=$(jq -r '.rooms[0].id' "$BODY")
# the ballot speaks in room order: og/oo/cg/co, speakers from dropdowns
WINNER_NAME=$(jq -r '.rooms[0].teams[1].name' "$BODY")
echo "room: $ROOM, top scores go to position 2 ($WINNER_NAME)"

# 8 x {position, speaker_participant_id, iron, score}. Tie first:
# every team totals 151 -> rejected. Then distinct totals, position
# 2 highest -> rank 1 -> winner.
TIE_SCORES=$(jq -c '[.rooms[0].teams | to_entries[]
  | (.key + 1) as $p | [.value.speakers[].id] as $ids
  | {position:$p, speaker_participant_id:$ids[0], iron:false, score:76},
    {position:$p, speaker_participant_id:$ids[1], iron:false, score:75}]' "$BODY")
SCORES=$(jq -c '[.rooms[0].teams | to_entries[]
  | (.key + 1) as $p | [.value.speakers[].id] as $ids
  | ({"1":76,"2":79,"3":75,"4":74}[$p|tostring]) as $base
  | {position:$p, speaker_participant_id:$ids[0], iron:false, score:$base},
    {position:$p, speaker_participant_id:$ids[1], iron:false, score:($base-1)}]' "$BODY")

# ----------------------------------------------------------------
say "the judge posts the motion, then the scored ballot"
# ----------------------------------------------------------------
assert j1 POST "/api/cab/v1/rooms/$ROOM/motion" 200 '.motion.text' \
  "THW walk through REST $RUN" \
  "{\"session_uuid\":\"$SESSION\",\"motion_text\":\"THW walk through REST $RUN\"}"

say "ballot permissions and tie rejection"
assert s1 POST "/api/cab/v1/rooms/$ROOM/ballot" 403 '.error' forbidden \
  "{\"session_uuid\":\"$SESSION\",\"scores\":$SCORES}"
assert j1 POST "/api/cab/v1/rooms/$ROOM/ballot" 422 \
  '.details.scores | contains("151")' true \
  "{\"session_uuid\":\"$SESSION\",\"scores\":$TIE_SCORES}"

say "the judge submits 8 speaks; ranks derive, the room confirms"
assert j1 POST "/api/cab/v1/rooms/$ROOM/ballot" 200 '.status' confirmed \
  "{\"session_uuid\":\"$SESSION\",\"scores\":$SCORES}"

# ----------------------------------------------------------------
say "ballot correction: only the head edits a confirmed ballot"
# ----------------------------------------------------------------
assert j1 POST "/api/cab/v1/rooms/$ROOM/ballot" 403 '.error' forbidden \
  "{\"session_uuid\":\"$SESSION\",\"scores\":$SCORES}"
assert head POST "/api/cab/v1/rooms/$ROOM/ballot" 200 '.status' confirmed \
  "{\"session_uuid\":\"$SESSION\",\"scores\":$SCORES}"

# ----------------------------------------------------------------
say "feedback: one per team on its adjudicator, hidden from them until finish"
# ----------------------------------------------------------------
assert s1 POST "/api/cab/v1/rooms/$ROOM/feedback" 422 'has("error")' true \
  "{\"session_uuid\":\"$SESSION\",\"accuracy\":7,\"reasoning\":8,\"discussion\":\"\"}"
assert s1 POST "/api/cab/v1/rooms/$ROOM/feedback" 201 '.status' sent \
  "{\"session_uuid\":\"$SESSION\",\"accuracy\":7,\"reasoning\":8,\"discussion\":\"Clear call, thin weighing $RUN\"}"
assert s2 POST "/api/cab/v1/rooms/$ROOM/feedback" 409 'has("error")' true \
  "{\"session_uuid\":\"$SESSION\",\"accuracy\":3,\"reasoning\":3,\"discussion\":\"second try\"}"
assert s1 GET "/api/cab/v1/sessions/$SESSION/feedback" 200 '.feedback[0].score' 7.5
assert j1 GET "/api/cab/v1/sessions/$SESSION/feedback" 200 '.on_your_adjudication | length' 0
assert head GET "/api/cab/v1/sessions/$SESSION/feedback" 200 '.feedback[0].team | type' string
assert head GET "/api/cab/v1/sessions/$SESSION/feedback" 200 '.progress[0].sent' 1

# ----------------------------------------------------------------
say "head finishes; history shows the winner"
# ----------------------------------------------------------------
assert head POST "/api/cab/v1/sessions/$SESSION/finish" 200 '.status' completed
# the adjudicator now reads it: anonymous, base 5 counting as one vote
assert j1 GET "/api/cab/v1/sessions/$SESSION/feedback" 200 '.on_your_adjudication | length' 1
assert j1 GET "/api/cab/v1/sessions/$SESSION/feedback" 200 '.on_your_adjudication[0] | has("team")' false
assert j1 GET "/api/cab/v1/sessions/$SESSION/feedback" 200 '.your_average' 6.25
assert s3 POST "/api/cab/v1/rooms/$ROOM/feedback" 409 'has("error")' true \
  "{\"session_uuid\":\"$SESSION\",\"accuracy\":6,\"reasoning\":6,\"discussion\":\"too late\"}"
assert j1 GET "/api/cab/v1/sessions/$SESSION" 200 '.stage' done
assert head GET "/api/cab/v1/clubs/$CLUB" 200 \
  ".history | map(select(.session_uuid == \"$SESSION\")) | .[0].winner" "$WINNER_NAME"

# ----------------------------------------------------------------
say "session detail: API twin + the public HTML page"
# ----------------------------------------------------------------
assert j1 GET "/api/cab/v1/sessions/$SESSION" 200 '.winner' "$WINNER_NAME"
assert j1 GET "/api/cab/v1/sessions/$SESSION" 200 '.name' "Walkthrough night $RUN"
assert j1 GET "/api/cab/v1/sessions/$SESSION" 200 \
  '.rooms[0].teams | map(select(.rank == 1)) | length' 1

# the public P6 page needs no identity at all ("&" arrives HTML-escaped)
: > "$JARS/anon"
WINNER_HTML=$(printf '%s' "$WINNER_NAME" | sed 's/&/\&amp;/g')
req anon GET "/c/$CLUB/s/$SESSION"
[ "$STATUS" = "200" ] || fail "GET /c/$CLUB/s/$SESSION anonymous: status $STATUS, want 200"
grep -q "Walkthrough night $RUN" "$BODY" || fail "session detail page misses the session name"
grep -q "$WINNER_HTML" "$BODY" || fail "session detail page misses the winner"
grep -q "THW walk through REST $RUN" "$BODY" || fail "session detail page misses the motion"
STEP=$((STEP + 1))
printf 'ok %2d  %-5s %-55s %s  %s\n' "$STEP" GET "/c/$CLUB/s/$SESSION" 200 "name+winner+motion"

# ----------------------------------------------------------------
say "M8a pages: /signin, the auth walls, the sidenav shell, standings rule 0"
# ----------------------------------------------------------------
req anon GET "/signin"
[ "$STATUS" = "200" ] || fail "GET /signin: status $STATUS, want 200"
grep -q 'id="signin-github"' "$BODY" || fail "/signin misses the GitHub provider button"
grep -q 'Continue with Google' "$BODY" || fail "/signin misses the Google (soon) button"
html_ok "P1 provider buttons" GET "/signin" 200

# every anonymous auth wall redirects to /signin - never to the provider
WALL=$(curl -s -o /dev/null -w '%{redirect_url}' "$BASE/account")
case "$WALL" in */signin) : ;; *) fail "anon account wall went to '$WALL', want /signin" ;; esac
html_ok "anon /account -> /signin" GET "/account" 302

# a public club's roster is readable by anyone
req anon GET "/c/$CLUB/members"
[ "$STATUS" = "200" ] || fail "GET /c/$CLUB/members anonymous: status $STATUS, want 200"
html_ok "public roster" GET "/c/.../members" 200

# club standings: the four tabs, engine calculated output VERBATIM
req anon GET "/c/$CLUB/standings/teams"
[ "$STATUS" = "200" ] || fail "GET /c/$CLUB/standings/teams: status $STATUS, want 200"
grep -q 'id="standings-tabs"' "$BODY" || fail "club standings misses the tab row"
grep -q 'id="standings-teams"' "$BODY" || fail "club standings misses the teams table"
grep -q "$WINNER_HTML" "$BODY" || fail "teams tab misses the winning team (engine passthrough)"
grep -qi "win rate\|winrate\|wins<" "$BODY" && fail "standings page carries cab-side win math"
html_ok "club standings teams (rule 0)" GET "/c/$CLUB/standings/teams" 200

req anon GET "/c/$CLUB/standings/adjudicators"
[ "$STATUS" = "200" ] || fail "GET /c/$CLUB/standings/adjudicators: status $STATUS, want 200"
grep -q "Rooms adjudicated" "$BODY" || fail "adjudicators tab misses the plain chair count"
html_ok "club standings adjudicators (plain count)" GET "/c/$CLUB/standings/adjudicators" 200

# global standings: the same four tabs, platform-wide latest finished
req anon GET "/standings/teams"
[ "$STATUS" = "200" ] || fail "GET /standings/teams: status $STATUS, want 200"
grep -q 'id="standings-tabs"' "$BODY" || fail "global standings misses the tab row"
html_ok "global standings teams" GET "/standings/teams" 200
req anon GET "/standings/clubs"
[ "$STATUS" = "200" ] || fail "GET /standings/clubs: status $STATUS, want 200"
grep -q 'id="standings-clubs"' "$BODY" || fail "clubs tab misses the plain counts table"
html_ok "global standings clubs" GET "/standings/clubs" 200

# the owner's club page: edit in place, the archive, the open form
req head GET "/c/$CLUB/owner"
[ "$STATUS" = "200" ] || fail "GET /c/$CLUB/owner: status $STATUS, want 200"
grep -q 'id="club-profile-form"' "$BODY" || fail "/owner misses the edit-in-place club form"
grep -q 'id="club-sessions"' "$BODY" || fail "/owner misses the Club Sessions archive"
grep -q 'id="open-session-form"' "$BODY" || fail "/owner misses the open-session form"
grep -q "Open new session" "$BODY" || fail "/owner misses Open new session"
html_ok "club edit + archive + open form (owner)" GET "/c/$CLUB/owner" 200

# /account is the profile page; /admin does not exist for non-admins
req head GET "/account"
[ "$STATUS" = "200" ] || fail "GET /account: status $STATUS, want 200"
grep -q 'id="account-form"' "$BODY" || fail "/account misses the profile form"
html_ok "/account profile page" GET "/account" 200
req head GET "/admin"
[ "$STATUS" = "404" ] || fail "GET /admin as non-admin: status $STATUS, want 404"
html_ok "/admin hidden from non-admins" GET "/admin" 404

# the anonymous front page lists the club in the directory (sidenav shell)
req anon GET "/"
[ "$STATUS" = "200" ] || fail "GET / anonymous: status $STATUS, want 200"
grep -q 'id="clubs-directory"' "$BODY" || fail "front page misses the clubs directory"
grep -q 'id="sidenav"' "$BODY" || fail "front page misses the sidenav shell"
html_ok "front page directory + sidenav" GET "/" 200

# ----------------------------------------------------------------
say "iron run: 9 speakers, one 1-speaker team, iron ballot, winner"
# ----------------------------------------------------------------
assert head POST "/api/cab/v1/clubs/$CLUB/sessions" 201 '.uuid | length' 36 \
  "{\"name\":\"Iron night $RUN\"}"
IRON_SESSION=$(jq -r '.uuid' "$BODY")

for u in s1 s2 s3 s4 s5 s6 s7 s8 x1; do
  assert "$u" POST "/api/cab/v1/sessions/$IRON_SESSION/signups" 201 '.participant_id | type' number '{}'
done
assert j1 POST "/api/cab/v1/sessions/$IRON_SESSION/signups" 201 '.participant_id | type' number '{}'
assert head POST "/api/cab/v1/sessions/$IRON_SESSION/close-signups" 200 '.stage' closed

# compose explicitly: 3 pairs + ONE 1-speaker team (iron), 2 sit out
assert head GET "/api/cab/v1/sessions/$IRON_SESSION" 200 '.signups | length' 10
IRON_COMPOSE=$(jq -c '
  ([.signups[] | select(.name | test("-s[1-8]$")) | .id] | sort) as $s
  | (.signups[] | select(.name | endswith("-j1")) | .id) as $j
  | {rooms: [{adjudicator_participant_id: $j,
              teams: [[$s[0], $s[1]], [$s[2], $s[3]], [$s[4], $s[5]], [$s[6]]]}]}' "$BODY")
assert head POST "/api/cab/v1/sessions/$IRON_SESSION/rooms" 201 '.rooms_created' 1 "$IRON_COMPOSE"
assert head GET "/api/cab/v1/sessions/$IRON_SESSION" 200 '.stage' running

# the iron team occupies BOTH engine speaker slots with one person
assert head GET "/api/cab/v1/sessions/$IRON_SESSION" 200 \
  '.rooms[0].teams[3].speakers | map(.id) | unique | length' 1
IRON_ROOM=$(jq -r '.rooms[0].id' "$BODY")

say "the seat decides the role; only the waitlist can be removed"
# j1 registered without a role; sitting in the chair made them the adjudicator
assert head GET "/api/cab/v1/sessions/$IRON_SESSION" 200 \
  '.signups | map(select(.name | endswith("-j1"))) | .[0].role' adjudicator
SEATED_PID=$(jq -r '[.signups[] | select(.name | endswith("-s1")) | .id][0]' "$BODY")
WAITING_PID=$(jq -r '[.signups[] | select(.name | endswith("-x1")) | .id][0]' "$BODY")
assert head DELETE "/api/cab/v1/sessions/$IRON_SESSION/signups/$SEATED_PID" 409 \
  '.error | contains("seated in a room")' true
assert head DELETE "/api/cab/v1/sessions/$IRON_SESSION/signups/$WAITING_PID" 200 '.status' removed
assert head GET "/api/cab/v1/sessions/$IRON_SESSION" 200 '.signups | length' 9
req head GET "/api/cab/v1/sessions/$IRON_SESSION"
IRON_WINNER=$(jq -r '.rooms[0].teams[3].name' "$BODY")
echo "iron room: $IRON_ROOM, the iron team ($IRON_WINNER) takes rank 1"

# 8 scores; position 4 rows BOTH name the single speaker, iron on the
# second speech; the iron team totals highest -> rank 1
# (computed from the session body BEFORE the motion POST overwrites it)
IRON_SCORES=$(jq -c '[.rooms[0].teams | to_entries[]
  | (.key + 1) as $p | [.value.speakers[].id] as $ids
  | ({"1":76,"2":75,"3":74,"4":80}[$p|tostring]) as $base
  | {position:$p, speaker_participant_id:$ids[0], iron:false, score:$base},
    {position:$p, speaker_participant_id:$ids[1], iron:($ids[0] == $ids[1]),
     score:($base-1)}]' "$BODY")

assert j1 POST "/api/cab/v1/rooms/$IRON_ROOM/motion" 200 '.motion.text' \
  "THW iron solo $RUN" \
  "{\"session_uuid\":\"$IRON_SESSION\",\"motion_text\":\"THW iron solo $RUN\"}"
# publishing starts 15 minutes of prep
assert j1 GET "/api/cab/v1/sessions/$IRON_SESSION" 200 '.rooms[0].motion.prep_until | type' string
req anon GET "/c/$CLUB/s/$IRON_SESSION/rooms/$IRON_ROOM"
grep -q 'data-prep-deadline=' "$BODY" || fail "room page misses the prep clock"
html_ok "prep clock on the room page" GET "/c/.../s/.../rooms/$IRON_ROOM" 200

assert j1 POST "/api/cab/v1/rooms/$IRON_ROOM/ballot" 200 '.status' confirmed \
  "{\"session_uuid\":\"$IRON_SESSION\",\"scores\":$IRON_SCORES}"

assert head POST "/api/cab/v1/sessions/$IRON_SESSION/finish" 200 '.status' completed
assert head GET "/api/cab/v1/sessions/$IRON_SESSION" 200 '.stage' done
assert head GET "/api/cab/v1/sessions/$IRON_SESSION" 200 '.winner' "$IRON_WINNER"
# history lists events in creation order - the iron night is last
assert head GET "/api/cab/v1/clubs/$CLUB" 200 \
  ".history | map(select(.session_uuid == \"$IRON_SESSION\")) | .[0].winner" "$IRON_WINNER"

req anon GET "/c/$CLUB/s/$IRON_SESSION"
[ "$STATUS" = "200" ] || fail "GET /c/$CLUB/s/$IRON_SESSION: status $STATUS, want 200"
grep -q "$IRON_WINNER" "$BODY" || fail "iron session detail page misses the winner"
STEP=$((STEP + 1))
printf 'ok %2d  %-5s %-55s %s  %s\n' "$STEP" GET "/c/$CLUB/s/$IRON_SESSION" 200 "iron winner"

# the judge's My page carries the night from the engine's history
req j1 GET "/me"
[ "$STATUS" = "200" ] || fail "GET /me as j1: status $STATUS, want 200"
grep -q 'id="me-history"' "$BODY" || fail "My page misses the history table"
grep -q "adjudicated" "$BODY" || fail "j1's My page misses the adjudicated night"
html_ok "judge's My page history" GET "/me" 200

# ----------------------------------------------------------------
say "M6 guest access: shared registration URL + personal links"
# ----------------------------------------------------------------
assert head POST "/api/cab/v1/clubs/$CLUB/sessions" 201 '.uuid | length' 36 \
  "{\"name\":\"Guest night $RUN\"}"
GSESSION=$(jq -r '.uuid' "$BODY")

# 6 member speakers leave two speaker seats for the guests
for u in s1 s2 s3 s4 s5 s6; do
  assert "$u" POST "/api/cab/v1/sessions/$GSESSION/signups" 201 '.participant_id | type' number '{}'
done

# the interim owner session surface: registration + signups + rooms
req head GET "/c/$CLUB/owner/s/$GSESSION"
[ "$STATUS" = "200" ] || fail "GET /c/$CLUB/owner/s/$GSESSION: status $STATUS, want 200"
grep -q 'id="shared-registration-url"' "$BODY" || fail "owner surface misses the shared URL"
grep -q 'id="session-people"' "$BODY" || fail "owner surface misses the people table"
grep -q "Start session" "$BODY" || fail "owner surface misses the Start session segment"
html_ok "owner session surface" GET "/c/$CLUB/owner/s/\$sess" 200

say "anonymous shared URL -> the registration form (no account)"
: > "$JARS/g1"; : > "$JARS/g2"; : > "$JARS/late"; : > "$JARS/anon2"
reqc g1 GET "/r/$GSESSION"
[ "$STATUS" = "200" ] || fail "GET /r/$GSESSION anonymous: status $STATUS, want 200"
grep -q 'id="guest-register-form"' "$BODY" || fail "shared URL misses the registration form"
html_ok "registration form" GET "/r/$GSESSION" 200

# register_guest <jar> <name> <as> - browser form flow: GET for the
# session+csrf, POST, personal /l/<code> link scraped into $PERSONAL
register_guest() {
  rg_jar="$1"; rg_name="$2"; rg_as="$3"
  reqc "$rg_jar" GET "/r/$GSESSION"
  [ "$STATUS" = "200" ] || fail "GET /r/$GSESSION ($rg_jar): status $STATUS, want 200"
  rg_tok=$(csrf)
  [ -n "$rg_tok" ] || fail "no csrf token on the registration form"
  STATUS=$(curl -s -o "$BODY" -w '%{http_code}' -b "$JARS/$rg_jar" -c "$JARS/$rg_jar" \
    --data-urlencode "_csrf_token=$rg_tok" --data-urlencode "name=$rg_name" \
    "$BASE/r/$GSESSION")
  [ "$STATUS" = "200" ] || fail "POST /r/$GSESSION ($rg_jar): status $STATUS, want 200"
  PERSONAL=$(grep -o '/l/[A-Za-z0-9_-]\{30,\}' "$BODY" | head -1)
  [ -n "$PERSONAL" ] || fail "no personal link on the registered page ($rg_jar)"
  grep -q "acts as you" "$BODY" || fail "registered page misses the keep-it warning"
  html_ok "guest $rg_as registered, link issued" POST "/r/$GSESSION" 200
}

say "two guests register: one speaker, one judge"
register_guest g1 "Guest Greta" speak;  G1_LINK=$PERSONAL
register_guest g2 "Guest Judy"  judge;  G2_LINK=$PERSONAL

say "personal links adopt the identity and land on P6; the registration shows there"
reqc anon2 GET "$G1_LINK"
[ "$STATUS" = "302" ] || fail "GET $G1_LINK anonymous: status $STATUS, want 302 to P6"
req anon2 GET "/c/$CLUB/s/$GSESSION"
[ "$STATUS" = "200" ] || fail "GET P6 as guest g1: status $STATUS, want 200"
grep -q "registered for this session" "$BODY" || fail "P6 misses the guest registration"
html_ok "guest link -> P6 + registration" GET "/l/<g1> -> /c/.../s/..." 200
reqc anon2 GET "$G2_LINK"
[ "$STATUS" = "302" ] || fail "GET $G2_LINK anonymous: status $STATUS, want 302 to P6"
req anon2 GET "/c/$CLUB/s/$GSESSION"
[ "$STATUS" = "200" ] || fail "GET P6 as guest g2: status $STATUS, want 200"
grep -q "registered for this session" "$BODY" || fail "P6 misses the guest registration"
html_ok "second guest link -> P6 + registration" GET "/l/<g2> -> /c/.../s/..." 200

say "head lists the links; a guest link opens NOTHING beyond its scope"
assert head GET "/api/cab/v1/sessions/$GSESSION/links" 200 '.links | length' 2

# visiting the personal link signs the browser session in as the guest
reqc g1 GET "$G1_LINK"
[ "$STATUS" = "302" ] || fail "GET $G1_LINK (g1): status $STATUS, want 302 to P6"
assert g1 GET "/api/cab/v1/sessions/$GSESSION/links" 403 '.error' forbidden
req g1 GET "/c/$CLUB/owner"
[ "$STATUS" = "403" ] || fail "GET /c/$CLUB/owner as guest: status $STATUS, want 403"
html_ok "guest on owner tree -> 403" GET "/c/.../owner" 403
req g1 GET "/c/$CLUB/members"
[ "$STATUS" = "200" ] || fail "GET /c/$CLUB/members as guest: status $STATUS, want 200"
html_ok "guest reads a public club's roster -> 200" GET "/c/.../members" 200
# a room of ANOTHER session does not exist on this session's P6 page
reqc g2 GET "$G2_LINK"
req g2 GET "/c/$CLUB/s/$GSESSION/rooms/$IRON_ROOM/ballot"
[ "$STATUS" = "404" ] || fail "foreign room on P6: status $STATUS, want 404"
html_ok "foreign-session room -> 404" GET "/c/.../s/<guest>/rooms/<iron>" 404

say "a guest added by hand leaves: one remove, link 404, no name kept"
assert head POST "/api/cab/v1/sessions/$GSESSION/links" 201 '.url | contains("/l/")' true \
  '{"name":"Leaving Lev"}'
LEV_LINK=$(jq -r '.url' "$BODY" | sed 's#^https*://[^/]*##')
assert head GET "/api/cab/v1/sessions/$GSESSION" 200 \
  '.signups | map(select(.name == "Leaving Lev")) | length' 1
LEV_PID=$(jq -r '.signups[] | select(.name == "Leaving Lev") | .id' "$BODY")
assert s1 DELETE "/api/cab/v1/sessions/$GSESSION/signups/$LEV_PID" 403 '.error' forbidden
assert head DELETE "/api/cab/v1/sessions/$GSESSION/signups/$LEV_PID" 200 '.status' removed
req anon2 GET "$LEV_LINK"
[ "$STATUS" = "404" ] || fail "removed guest's $LEV_LINK: status $STATUS, want 404"
html_ok "removed guest's link -> 404" GET "/l/<lev>" 404
assert head GET "/api/cab/v1/sessions/$GSESSION" 200 \
  '.signups | map(select(.name == "Leaving Lev")) | length' 0
assert head POST "/api/cab/v1/sessions/$GSESSION/links" 201 '.url | contains("/l/")' true \
  '{"name":"Handed Hanna"}'
assert head GET "/api/cab/v1/sessions/$GSESSION/links" 200 '.links | length' 3

say "close sign-ups: the shared URL turns into the closed notice"
reqc late GET "/r/$GSESSION"
LATE_TOK=$(csrf)
assert head POST "/api/cab/v1/sessions/$GSESSION/close-signups" 200 '.stage' closed
req anon2 GET "/r/$GSESSION"
[ "$STATUS" = "200" ] || fail "GET /r/$GSESSION after close: status $STATUS, want 200"
grep -q "Registration is closed" "$BODY" || fail "shared URL misses the closed notice"
html_ok "closed notice" GET "/r/$GSESSION" 200
STATUS=$(curl -s -o "$BODY" -w '%{http_code}' -b "$JARS/late" -c "$JARS/late" \
  --data-urlencode "_csrf_token=$LATE_TOK" --data-urlencode "name=Late Larry" \
  "$BASE/r/$GSESSION")
[ "$STATUS" = "200" ] || fail "POST /r/$GSESSION after close: status $STATUS, want 200"
grep -q "Registration is closed" "$BODY" || fail "late registration got past the gate"
html_ok "registration after close -> closed notice" POST "/r/$GSESSION" 200
assert head GET "/api/cab/v1/sessions/$GSESSION/links" 200 '.links | length' 3

say "compose including guests; the guest judge chairs the room"
assert head GET "/api/cab/v1/sessions/$GSESSION" 200 '.signups | length' 9
GCOMPOSE=$(jq -c '
  ([.signups[] | select(.name != "Guest Judy") | .id] | sort) as $s
  | (.signups[] | select(.name == "Guest Judy") | .id) as $j
  | {rooms: [{adjudicator_participant_id: $j,
              teams: [$s[0:2], $s[2:4], $s[4:6], $s[6:8]]}]}' "$BODY")
assert head POST "/api/cab/v1/sessions/$GSESSION/rooms" 201 '.rooms_created' 1 "$GCOMPOSE"
assert head GET "/api/cab/v1/sessions/$GSESSION" 200 '.stage' running
GROOM=$(jq -r '.rooms[0].id' "$BODY")
# speakers in table order og1 og2 oo1 oo2 cg1 cg2 co1 co2
GPIDS=$(jq -r '.rooms[0].teams[].speakers[].id' "$BODY")
set -- $GPIDS
GWINNER=$(jq -r '.rooms[0].teams[0].name' "$BODY")

say "the guest judge fills the ballot through P6 (identity from the link)"
reqc g2 GET "$G2_LINK"
[ "$STATUS" = "302" ] || fail "GET $G2_LINK (g2): status $STATUS, want 302 to P6"
reqc g2 GET "/c/$CLUB/s/$GSESSION"
[ "$STATUS" = "200" ] || fail "GET P6 as the guest judge: status $STATUS, want 200"
grep -q "Fill ballot" "$BODY" && fail "a ballot is offered before the room's motion"
html_ok "no ballot before the motion" GET "/c/.../s/<guest-night>" 200
# the guest chair publishes the motion on the room page (cab checks the
# seat, the engine sees the club head)
reqc g2 GET "/c/$CLUB/s/$GSESSION/rooms/$GROOM"
G2_TOK=$(csrf)
STATUS=$(curl -s -o "$BODY" -w '%{http_code}' -b "$JARS/g2" -c "$JARS/g2" \
  --data-urlencode "_csrf_token=$G2_TOK" --data-urlencode "motion_text=THW let guests chair $RUN" \
  "$BASE/c/$CLUB/s/$GSESSION/rooms/$GROOM/motion")
[ "$STATUS" = "302" ] || fail "guest motion POST: status $STATUS, want 302"
html_ok "guest chair publishes the motion" POST "/c/.../s/.../rooms/$GROOM/motion" 302
reqc g2 GET "/c/$CLUB/s/$GSESSION"
grep -q "Fill ballot" "$BODY" || fail "P6 misses the guest judge's Fill ballot segment"
reqc g2 GET "/c/$CLUB/s/$GSESSION/rooms/$GROOM/ballot"
[ "$STATUS" = "200" ] || fail "GET P6 ballot page: status $STATUS, want 200"
grep -q 'class="ballot"' "$BODY" || fail "guest ballot page misses the ballot"
html_ok "guest ballot page via P6" GET "/c/.../s/.../rooms/$GROOM/ballot" 200
G2_TOK=$(csrf)
# og totals highest -> rank 1; all totals distinct
STATUS=$(curl -s -o "$BODY" -w '%{http_code}' -b "$JARS/g2" -c "$JARS/g2" \
  --data-urlencode "_csrf_token=$G2_TOK" \
  --data-urlencode "ballot[og][PM][speaker]=$1"  --data-urlencode "ballot[og][PM][score]=79" \
  --data-urlencode "ballot[og][DPM][speaker]=$2" --data-urlencode "ballot[og][DPM][score]=78" \
  --data-urlencode "ballot[oo][LO][speaker]=$3"  --data-urlencode "ballot[oo][LO][score]=76" \
  --data-urlencode "ballot[oo][DLO][speaker]=$4" --data-urlencode "ballot[oo][DLO][score]=75" \
  --data-urlencode "ballot[cg][MG][speaker]=$5"  --data-urlencode "ballot[cg][MG][score]=75" \
  --data-urlencode "ballot[cg][GW][speaker]=$6"  --data-urlencode "ballot[cg][GW][score]=74" \
  --data-urlencode "ballot[co][MO][speaker]=$7"  --data-urlencode "ballot[co][MO][score]=73" \
  --data-urlencode "ballot[co][OW][speaker]=$8"  --data-urlencode "ballot[co][OW][score]=72" \
  "$BASE/c/$CLUB/s/$GSESSION/rooms/$GROOM/ballot")
[ "$STATUS" = "302" ] || fail "guest ballot POST: status $STATUS, want 302"
html_ok "guest ballot submitted via P6" POST "/c/.../s/.../rooms/$GROOM/ballot" 302
assert head GET "/api/cab/v1/sessions/$GSESSION" 200 '.rooms[0].status' confirmed
assert head GET "/api/cab/v1/sessions/$GSESSION" 200 '.winner' "$GWINNER"

say "finish; the public history shows the guests by display name"
assert head POST "/api/cab/v1/sessions/$GSESSION/finish" 200 '.status' completed
assert head GET "/api/cab/v1/sessions/$GSESSION" 200 '.stage' done
req anon2 GET "/c/$CLUB/s/$GSESSION"
[ "$STATUS" = "200" ] || fail "GET /c/$CLUB/s/$GSESSION: status $STATUS, want 200"
grep -q "Guest Greta" "$BODY" || fail "guest night page misses Guest Greta"
grep -q "Handed Hanna" "$BODY" || fail "guest night page misses Handed Hanna"
html_ok "guest names in history" GET "/c/.../s/<guest-night>" 200

say "Greta signs up for real and claims her guest night"
code=$(curl -s -o /dev/null -w '%{http_code}' -c "$JARS/claimer" \
  "$BASE/dev/switch-user?username=wt-$RUN-greta")
[ "$code" = "302" ] || fail "switch-user greta: status $code, want 302"
reqc claimer GET "$G1_LINK"
[ "$STATUS" = "200" ] || fail "GET $G1_LINK signed in: status $STATUS, want 200 (claim page)"
grep -q "Add to my account" "$BODY" || fail "personal link misses the claim offer for an account"
CLAIM_TOK=$(csrf)
html_ok "personal link offers the claim" GET "/l/<g1>" 200
STATUS=$(curl -s -o "$BODY" -w '%{http_code}' -b "$JARS/claimer" -c "$JARS/claimer" \
  --data-urlencode "_csrf_token=$CLAIM_TOK" "$BASE$G1_LINK/claim")
[ "$STATUS" = "302" ] || fail "POST $G1_LINK/claim: status $STATUS, want 302"
html_ok "claim accepted by the engine" POST "/l/<g1>/claim" 302
req claimer GET "/me"
grep -q 'id="me-history"' "$BODY" || fail "claimer's My page misses the history table"
grep -q "No sessions played yet" "$BODY" && fail "the claimed night is missing from My page"
html_ok "claimed night on My page" GET "/me" 200
req anon2 GET "$G1_LINK"
[ "$STATUS" = "404" ] || fail "claimed $G1_LINK: status $STATUS, want 404"
html_ok "claimed guest link is gone" GET "/l/<g1>" 404
req anon2 GET "/c/$CLUB/s/$GSESSION"
grep -q "wt-$RUN-greta" "$BODY" || fail "the guest night does not show the claimer's name"
html_ok "the night shows the real account's name" GET "/c/.../s/<guest-night>" 200

# ----------------------------------------------------------------
say "the head adds a registered non-member at once; they accept later"
# ----------------------------------------------------------------
code=$(curl -s -o /dev/null -w '%{http_code}' -c "$JARS/inv" \
  "$BASE/dev/switch-user?username=wt-$RUN-inv")
[ "$code" = "302" ] || fail "switch-user inv: status $code, want 302"
assert head POST "/api/cab/v1/clubs/$CLUB/sessions" 201 '.uuid | length' 36 \
  "{\"name\":\"Invite night $RUN\"}"
ISESSION=$(jq -r '.uuid' "$BODY")
assert head GET "/api/cab/v1/sessions/$ISESSION/people?q=wt-$RUN-inv" 200 '.users[0].username' "wt-$RUN-inv"
assert s1 POST "/api/cab/v1/sessions/$ISESSION/invitations" 403 '.error' forbidden "{\"user\":\"wt-$RUN-inv\"}"
assert head POST "/api/cab/v1/sessions/$ISESSION/invitations" 201 '.username' "wt-$RUN-inv" \
  "{\"user\":\"wt-$RUN-inv\"}"
# seated by name before accepting: the place is not theirs yet
assert head GET "/api/cab/v1/sessions/$ISESSION" 200 \
  ".signups | map(select(.name == \"wt-$RUN-inv\")) | length" 1
assert inv GET "/api/cab/v1/sessions/$ISESSION" 200 '.signups | map(select(.id)) | length' 0
reqc inv GET "/me"
ACCEPT=$(grep -o '/invitations/[0-9]*/accept' "$BODY" | head -1)
[ -n "$ACCEPT" ] || fail "My page misses the invitation"
INV_TOK=$(csrf)
html_ok "invitation on My page" GET "/me" 200
STATUS=$(curl -s -o "$BODY" -w '%{http_code}' -b "$JARS/inv" -c "$JARS/inv" \
  --data-urlencode "_csrf_token=$INV_TOK" "$BASE$ACCEPT")
[ "$STATUS" = "302" ] || fail "POST $ACCEPT: status $STATUS, want 302"
html_ok "invitation accepted (engine claim token)" POST "$ACCEPT" 302
assert inv GET "/api/cab/v1/sessions/$ISESSION" 200 '.signups | map(select(.id)) | length' 1
req inv GET "/c/$CLUB/s/$ISESSION"
grep -q "registered for this session" "$BODY" || fail "the accepted place is not theirs on the session page"
html_ok "accepted place is theirs" GET "/c/.../s/<invite-night>" 200
assert head DELETE "/api/cab/v1/sessions/$ISESSION" 200 '.status' cancelled

# ----------------------------------------------------------------
say "club management: profile PATCH (incl. the M8a profile columns) + member removal"
# ----------------------------------------------------------------
assert s1 PATCH "/api/cab/v1/clubs/$CLUB" 403 '.error' forbidden '{"name":"nope"}'
assert head PATCH "/api/cab/v1/clubs/$CLUB" 200 '.city' Lviv \
  "{\"name\":\"BP Walkthrough $RUN (renamed)\",\"city\":\"Lviv\",\"meeting_info\":\"Thursdays 18:30\",\"description\":\"BP practice club\",\"contacts\":\"@wtclub\"}"
assert head GET "/api/cab/v1/clubs/$CLUB" 200 '.name' "BP Walkthrough $RUN (renamed)"
assert head GET "/api/cab/v1/clubs/$CLUB" 200 '.meeting_info' "Thursdays 18:30"
assert head GET "/api/cab/v1/clubs/$CLUB" 200 '.contacts' "@wtclub"

# the club page shows the profile columns
req anon GET "/c/$CLUB"
[ "$STATUS" = "200" ] || fail "GET /c/$CLUB: status $STATUS, want 200"
grep -q "Thursdays 18:30" "$BODY" || fail "club page misses meeting_info"
grep -q "BP practice club" "$BODY" || fail "club page misses the description"
html_ok "club page profile columns" GET "/c/$CLUB" 200

assert head GET "/api/cab/v1/clubs/$CLUB/members" 200 '.members | length' 11
X1_UID=$(jq -r --arg name "wt-$RUN-x1" \
  '.members[] | select(.username == $name) | .user_id' "$BODY")
HEAD_UID=$(jq -r --arg name "wt-$RUN-head" \
  '.members[] | select(.username == $name) | .user_id' "$BODY")
assert s1 DELETE "/api/cab/v1/clubs/$CLUB/members/$X1_UID" 403 '.error' forbidden
assert head DELETE "/api/cab/v1/clubs/$CLUB/members/$X1_UID" 200 '.status' removed
assert head GET "/api/cab/v1/clubs/$CLUB/members" 200 '.members | length' 10
assert head DELETE "/api/cab/v1/clubs/$CLUB/members/$HEAD_UID" 422 \
  '.error | contains("head cannot be removed")' true

# ----------------------------------------------------------------
say "session cancel on a throwaway second session"
# ----------------------------------------------------------------
assert head POST "/api/cab/v1/clubs/$CLUB/sessions" 201 '.uuid | length' 36 \
  "{\"name\":\"Throwaway $RUN\"}"
SESSION2=$(jq -r '.uuid' "$BODY")
assert s1 DELETE "/api/cab/v1/sessions/$SESSION2" 403 '.error' forbidden
assert head DELETE "/api/cab/v1/sessions/$SESSION2" 200 '.status' cancelled
assert head GET "/api/cab/v1/sessions/$SESSION2" 404 '.error' "not found"

printf '\nWALKTHROUGH GREEN: %s steps, club %s\n' "$STEP" "$CLUB"
