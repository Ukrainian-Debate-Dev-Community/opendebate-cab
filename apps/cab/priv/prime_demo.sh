#!/usr/bin/env bash
# Prime a clickable demo world around a REAL signed-in user (dev only).
#
#   apps/cab/priv/prime_demo.sh <your_username>
#
# M8a shell: navigation lives in the LEFT SIDENAV (brand cap -> home;
# global: Clubs | Standings | Admin; club: Club | Rooms | Sessions |
# Standings | Members; profile block at the bottom -> /account).
# Your user is made a PLATFORM ADMIN so the Admin item is clickable.
#
# Creates:
#   Kyiv Debate Club  - YOU are head; 8 speakers + 1 judge approved and
#                       registered to an OPEN session (sign-ups OPEN).
#                       Click path: Members -> approve nina (her join
#                       answers are shown) -> Rooms (the live session)
#                       -> Close sign-ups -> Make/Compose rooms ->
#                       ballots -> Finish session -> Sessions (archive)
#                       and Standings (engine passthrough).
#   Lviv Debate Society - demo-lviv-head is head; you are NOT a member:
#                       Request to join runs through the JOIN FORM
#                       (about me + contact required), then
#                       /dev/switch-user?username=demo-lviv-head to
#                       approve yourself.
set -u
BASE="${BASE:-http://localhost:4000}"
# where `mix` runs; a project that holds cab as a submodule sets
# MIX_ROOT to itself so its own build is used
ROOT="${MIX_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
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

echo "== $ME becomes a platform admin (the sidenav Admin item + /admin)"
(cd "$ROOT" && nix develop --command sh -c \
  "mix run -e 'Cab.Repo.get_by!(Cab.Accounts.User, username: \"$ME\") |> Ecto.Changeset.change(is_admin: true) |> Cab.Repo.update!()'" \
  >/dev/null 2>&1) || fail "could not set is_admin on $ME"

echo "== Kyiv Debate Club (head: $ME)"
SEED_OUT=$(cd "$ROOT" && nix develop --command sh -c \
  "mix cab.seed_club 'Kyiv Debate Club' 'Kyiv' '$ME'" 2>&1) || { echo "$SEED_OUT"; fail "seed kyiv"; }
KYIV=$(printf '%s\n' "$SEED_OUT" | sed -n 's/^CLUB_UUID=//p' | tail -1)
[ -n "$KYIV" ] || fail "no kyiv uuid"
echo "   /c/$KYIV"

echo "== joins (with the REQUIRED form answers): 8 speakers + judge approved, nina PENDING"
for u in s1 s2 s3 s4 s5 s6 s7 s8 j1; do
  req "$u" POST "/api/cab/v1/clubs/$KYIV/join-requests" \
    "{\"message\":\"I am demo-$u and I want to debate\",\"contact\":\"@demo-$u\"}"
  [ "$STATUS" = "201" ] || fail "join $u: $STATUS"
  rid=$(jq -r '.id' "$BODY")
  req me PATCH "/api/cab/v1/join-requests/$rid" '{"action":"approve"}'
  [ "$STATUS" = "200" ] || fail "approve $u: $STATUS"
done
req nina POST "/api/cab/v1/clubs/$KYIV/join-requests" \
  '{"message":"Nina here, saw your club at the uni fair, want to try BP","contact":"@demo-nina"}'
[ "$STATUS" = "201" ] || fail "join nina: $STATUS"

echo "== open session + sign-ups (9 people; you seat the judge by dragging)"
req me POST "/api/cab/v1/clubs/$KYIV/sessions" '{"name":"Thursday practice"}'
[ "$STATUS" = "201" ] || fail "open session: $STATUS"
SESS=$(jq -r '.uuid' "$BODY")
echo "   shared registration URL (give this to guests): $BASE/r/$SESS"
for u in s1 s2 s3 s4 s5 s6 s7 s8; do
  req "$u" POST "/api/cab/v1/sessions/$SESS/signups" '{}'
  [ "$STATUS" = "201" ] || fail "signup $u: $STATUS"
done
req j1 POST "/api/cab/v1/sessions/$SESS/signups" '{}'
[ "$STATUS" = "201" ] || fail "signup j1: $STATUS"

echo "== Lviv Debate Society (you are an outsider)"
SEED_OUT=$(cd "$ROOT" && nix develop --command sh -c \
  "mix cab.seed_club 'Lviv Debate Society' 'Lviv' 'demo-lviv-head'" 2>&1) || { echo "$SEED_OUT"; fail "seed lviv"; }
LVIV=$(printf '%s\n' "$SEED_OUT" | sed -n 's/^CLUB_UUID=//p' | tail -1)
req lviv-m1 POST "/api/cab/v1/clubs/$LVIV/join-requests" \
  '{"message":"demo member for the roster","contact":"@demo-lviv-m1"}'
[ "$STATUS" = "201" ] || fail "lviv join m1: $STATUS"
rid=$(jq -r '.id' "$BODY")
req lviv-head PATCH "/api/cab/v1/join-requests/$rid" '{"action":"approve"}'
[ "$STATUS" = "200" ] || fail "lviv approve: $STATUS"

cat <<EOF

PRIMED. Your world ($ME), the M8a sidenav shell:

GLOBAL (sidenav: Clubs | Standings | Admin, profile at the bottom)
  home / cabinet   $BASE/
                   - clubs directory with the words "Tonight" column;
                     signed in it adds My clubs / My sessions
  sign-in          $BASE/signin
  standings        $BASE/standings/teams
                   - four tabs: Teams | Speakers | Judges | Clubs,
                     ONE session's engine output verbatim (latest
                     finished); nothing finished yet = the notice
  account          $BASE/account   (sidenav bottom: avatar + $ME)
  admin            $BASE/admin     (you are is_admin: clubs table,
                     create club, change head, archive)

KYIV, you are head (club sidenav: Club | Rooms | Sessions |
Standings | Members)
  club page        $BASE/c/$KYIV
  edit in place    $BASE/c/$KYIV/owner            (Save in the chrome)
  Rooms (live)     $BASE/c/$KYIV/owner/s/$SESS
                   - the owner surface: shared guest URL
                     $BASE/r/$SESS, signed-up list, add by hand;
                     Close sign-ups -> Make rooms or Compose rooms
                     (drag-and-drop; a 1-speaker team is an iron) ->
                     per-room ballots (you have full control; or act
                     as the judge: $BASE/dev/switch-user?username=demo-j1)
                     -> Finish session
  Sessions         $BASE/c/$KYIV/owner/sessions   (archive + Open new
                     session, the open form moved here)
  Members          $BASE/c/$KYIV/owner/members
                   - nina's request is PENDING with her form answers
                     (about me + contact), approve or decline
  Standings        $BASE/c/$KYIV/standings/teams  (same four tabs,
                     club-scoped; fills up after Finish session)
  session page     $BASE/c/$KYIV/s/$SESS          (public, stage-aware)

LVIV, you are an outsider
  club page        $BASE/c/$LVIV
                   - "Request to join" opens the JOIN FORM
                     ($BASE/c/$LVIV/join): about me + contact are
                     REQUIRED; then approve yourself as the head:
                     $BASE/dev/switch-user?username=demo-lviv-head
                     -> $BASE/c/$LVIV/owner/members

switch back        $BASE/dev/switch-user?username=$ME
EOF
