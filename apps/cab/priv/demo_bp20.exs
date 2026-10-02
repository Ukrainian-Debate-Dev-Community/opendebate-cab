# "BP Demo 20" — a ready-to-run 20-team BP tournament for the
# organiser cast user: 5 prelim rounds, 20 bot teams (40 shadow
# speakers), 5 bot judges plus the cast judge. Nothing is checked in
# and round 1 has not started, so the whole new flow (bulk check-in,
# power-paired draft draw, release, strict ballots, break, SF, GF)
# can be clicked through from the very beginning.
#
#     make fresh   (three-role demo), then:
#     cd platform && mix run apps/cab/priv/demo_bp20.exs

alias Cab.{DevSeeds, EngineApi}

check! = fn
  label, {:ok, value} ->
    IO.puts("  ok  #{label}")
    value

  label, {:error, reason} ->
    IO.puts("  FAIL #{label}: #{inspect(reason)}")
    raise "demo bp20 seed failed at: #{label}"
end

IO.puts("== BP Demo 20 (organiser-owned) ==")
organiser = check!.("cast user organiser", DevSeeds.bot_user("organiser"))
judge = check!.("cast user judge", DevSeeds.bot_user("judge"))
actor = organiser.node_user_id

%{"event" => event} =
  check!.("create tournament", EngineApi.create_tournament(actor, "BP Demo 20"))

for n <- 1..5 do
  check!.("round #{n}", EngineApi.create_round(actor, event["id"], "Round #{n}", n))
end

check!.("20 bot teams + 5 bot judges", DevSeeds.seed_tournament(actor, event["id"], 20, 5))

check!.(
  "cast judge joins",
  EngineApi.add_participant(actor, event["id"], "Judge (you)", "adjudicator", judge.node_user_id)
)

IO.puts("""

BP DEMO 20 READY — http://localhost:4000/t/#{event["id"]}
  organiser : run it — check-in (Everyone is here), make rooms,
              release draw, motion, ballots x5 rounds, break top 8,
              semifinals, grand final
  judge     : is one of the 6 judges
""")
