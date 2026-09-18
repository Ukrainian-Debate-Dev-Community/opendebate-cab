# Fresh demo data around the fixed three-role dev cast.
#
#     make fresh          (from the repo root: wipes both DBs, reseeds,
#                          restarts the stack, then runs this script)
#
# Creates:
#   - cast users: organiser / judge / speaker (the only three personas)
#   - "Demo Open": a 3-round tournament owned by organiser, with
#     7 bot teams + 1 bot judge, PLUS the cast judge as a judge and
#     the cast speaker on team "You & Partner" — so each persona has
#     something to see and do from round one
#   - "Demo Club": a club with an OPEN session and 7 bot speakers
#     signed up — speaker and judge personas complete the field from
#     the UI, organiser makes the rooms

alias Cab.{Clubs, DevSeeds, EngineApi}

check! = fn
  label, {:ok, value} ->
    IO.puts("  ok  #{label}")
    value

  label, {:error, reason} ->
    IO.puts("  FAIL #{label}: #{inspect(reason)}")
    raise "demo seed failed at: #{label}"
end

IO.puts("== Cast (organiser / judge / speaker) ==")
organiser = check!.("cast user organiser", DevSeeds.bot_user("organiser"))
judge = check!.("cast user judge", DevSeeds.bot_user("judge"))
speaker = check!.("cast user speaker", DevSeeds.bot_user("speaker"))
actor = organiser.node_user_id

IO.puts("== Demo Open (tournament) ==")
%{"event" => event} = check!.("create tournament", EngineApi.create_tournament(actor, "Demo Open"))

for n <- 1..3 do
  check!.("round #{n}", EngineApi.create_round(actor, event["id"], "Round #{n}", n))
end

speaker_participant =
  check!.(
    "cast speaker joins",
    EngineApi.add_participant(actor, event["id"], "Speaker (you)", "speaker", speaker.node_user_id)
  )

check!.(
  "cast judge joins",
  EngineApi.add_participant(actor, event["id"], "Judge (you)", "adjudicator", judge.node_user_id)
)

check!.("7 bot teams + 1 bot judge", DevSeeds.seed_tournament(actor, event["id"], 7, 1))

partner =
  check!.(
    "bot partner for the cast speaker",
    EngineApi.provision_participant(actor, event["id"], "Bot Partner", "speaker")
  )

check!.(
  "team You & Partner",
  EngineApi.create_team(actor, event["id"], "You & Partner", [
    speaker_participant["id"],
    partner["id"]
  ])
)

IO.puts("== Demo Club (open session) ==")
{:ok, club} = Clubs.create_club(%{name: "Demo Club", visible: true})
check!.("open session", Clubs.open_session(actor, club, "Club night"))
check!.("7 bot speakers signed up", DevSeeds.seed_club_signups(club.id, 7, 0))

IO.puts("""

DEMO READY — http://localhost:4000/
  organiser : owns "Demo Open" (8 teams, 2 judges) and hosts "Demo Club"
  speaker   : plays on "You & Partner"; can sign up to speak at the club
  judge     : judges "Demo Open"; can sign up to judge at the club
""")
