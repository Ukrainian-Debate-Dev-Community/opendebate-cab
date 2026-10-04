#!/usr/bin/env bash
# Prime a clickable demo world around a REAL signed-in user (dev only).
#
#   platform/apps/cab/priv/prime_demo.sh <your_username>
#
# Creates:
#   Kyiv Debate Club  - YOU are head; 8 speakers + 1 judge approved and
#                       registered to an OPEN session (sign-ups OPEN -
#                       the M5 flow waits for YOU to close them); 1 join
#                       request left pending for you to approve.
#                       Your click path: approve nina -> Close sign-ups
#                       -> Make rooms (or Compose rooms: drag chips
#                       into slots) -> fill ballots (as head: full
#                       control, or /dev/switch-user to demo-j1) ->
#                       Finish session -> history -> session page.
#   Lviv Debate Society - demo-lviv-head is head; you are NOT a member:
#                       request to join from the public page, then
#                       /dev/switch-user?username=demo-lviv-head to
#                       approve yourself (controlling other users).
set -u
BASE="${BASE:-http://localhost:4000}"
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
ME="${1:?usage: prime_demo.sh <your_username>}"
JARS="$(mktemp -d)"
BODY="$JARS/body.json"

fail() { printf 'FAIL: %s\nlast body: %s\n' "$*" "$(cat "$BODY" 2>/dev/null)"; exit 1; }

req() { # <jar> <method> <path> [json]
  jar="$1"; method="$2"; path="$3"; data="${4:-}"
  if [ -n "$data" ]; then
    STATUS=$(curl -s -o "$BODY" -w '%{http_code}' -b "$JARS/$jar" -X "$method" \
      -H 'content-type: application/json' -d "$data" "$BASE$path")
  else
    STATUS=$(curl -s -o "$BODY" -w '%{http_code}' -b "$JARS/$jar" -X "$method" "$BASE$path")
  fi
}

mkjar() { # <jar> <username>
  code=$(curl -s -o /dev/null -w '%{http_code}' -c "$JARS/$1" \
    "$BASE/dev/switch-user?username=$2")
  [ "$code" = "302" ] || fail "switch-user $2: $code"
}

echo "== demo users"
for u in s1 s2 s3 s4 s5 s6 s7 s8 j1 nina lviv-head lviv-m1; do
  mkjar "$u" "demo-$u"
done
mkjar me "$ME"

echo "== Kyiv Debate Club (head: $ME)"
SEED_OUT=$(cd "$ROOT/platform" && nix develop --command sh -c \
  "mix cab.seed_club 'Kyiv Debate Club' 'Kyiv' '$ME'" 2>&1) || { echo "$SEED_OUT"; fail "seed kyiv"; }
KYIV=$(printf '%s\n' "$SEED_OUT" | sed -n 's/^CLUB_UUID=//p' | tail -1)
[ -n "$KYIV" ] || fail "no kyiv uuid"
echo "   /c/$KYIV"

echo "== joins: 8 speakers + judge approved, nina left PENDING for you"
for u in s1 s2 s3 s4 s5 s6 s7 s8 j1; do
  req "$u" POST "/api/v1/clubs/$KYIV/join-requests"
  [ "$STATUS" = "201" ] || fail "join $u: $STATUS"
  rid=$(jq -r '.id' "$BODY")
  req me PATCH "/api/v1/join-requests/$rid" '{"action":"approve"}'
  [ "$STATUS" = "200" ] || fail "approve $u: $STATUS"
done
req nina POST "/api/v1/clubs/$KYIV/join-requests"
[ "$STATUS" = "201" ] || fail "join nina: $STATUS"

echo "== open session + sign-ups (8 speak, 1 judge)"
req me POST "/api/v1/clubs/$KYIV/sessions" '{"name":"Thursday practice"}'
[ "$STATUS" = "201" ] || fail "open session: $STATUS"
SESS=$(jq -r '.uuid' "$BODY")
echo "   shared registration URL (give this to guests): $BASE/r/$SESS"
for u in s1 s2 s3 s4 s5 s6 s7 s8; do
  req "$u" POST "/api/v1/sessions/$SESS/signups" '{"as":"speak"}'
  [ "$STATUS" = "201" ] || fail "signup $u: $STATUS"
done
req j1 POST "/api/v1/sessions/$SESS/signups" '{"as":"judge"}'
[ "$STATUS" = "201" ] || fail "signup j1: $STATUS"

echo "== Lviv Debate Society (you are an outsider)"
SEED_OUT=$(cd "$ROOT/platform" && nix develop --command sh -c \
  "mix cab.seed_club 'Lviv Debate Society' 'Lviv' 'demo-lviv-head'" 2>&1) || { echo "$SEED_OUT"; fail "seed lviv"; }
LVIV=$(printf '%s\n' "$SEED_OUT" | sed -n 's/^CLUB_UUID=//p' | tail -1)
req lviv-m1 POST "/api/v1/clubs/$LVIV/join-requests"
[ "$STATUS" = "201" ] || fail "lviv join m1: $STATUS"
rid=$(jq -r '.id' "$BODY")
req lviv-head PATCH "/api/v1/join-requests/$rid" '{"action":"approve"}'
[ "$STATUS" = "200" ] || fail "lviv approve: $STATUS"

cat <<EOF

PRIMED. Your world ($ME):
  cabinet        $BASE/
  Kyiv (head)    $BASE/c/$KYIV/owner
                 - 1 pending request (demo-nina): approve or decline
                 - session "Thursday practice" with sign-ups OPEN,
                   8 speakers + 1 judge registered.
                 - guest registration (M6): the owner page's
                   REGISTRATION section carries the shareable URL
                   $BASE/r/$SESS
                   - anyone opens it, registers by name, and gets a
                   personal /l/<code> link that IS their access
                   (issue, copy and revoke links from that section).
                   Click CLOSE SIGN-UPS,
                   then Make rooms (auto) or Compose rooms
                   (drag-and-drop chips into slots; a 1-speaker team
                   is an iron) -> per-room ballots (you have full
                   control; or act as the judge:
                   $BASE/dev/switch-user?username=demo-j1)
                 - Finish session -> winner in history -> click the
                   history row for the public session page
  Lviv (public)  $BASE/c/$LVIV
                 - Request to join, then approve yourself as the head:
                   $BASE/dev/switch-user?username=demo-lviv-head
  switch back    $BASE/dev/switch-user?username=$ME
EOF
