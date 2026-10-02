# BP acceptance walkthrough against a LIVE engine (make up first):
# 20 teams / 40 speakers / 5 judges, 5 power-paired rounds (draft ->
# release draw, motions, strict ballots), break top 8 -> 2 semifinals
# -> grand final -> champion. Exercises every ADOPT-NOW behavior.
#
#     cd platform && mix run apps/cab/priv/walkthrough_bp20.exs

Code.require_file("walk.exs", __DIR__)

alias Cab.{EngineApi, Tournaments}

stamp = System.os_time(:second)

IO.puts("== 0. Actor ==")
td = Walk.gateway_user!("td-bp20")
actor = td.node_user_id

IO.puts("== 1. Tournament: 5 prelim rounds ==")

%{"event" => event} =
  Walk.check!("create_tournament", EngineApi.create_tournament(actor, "BP Walkthrough #{stamp}"))

event_id = event["id"]

for n <- 1..5 do
  Walk.check!("round #{n}", EngineApi.create_round(actor, event_id, "Round #{n}", n))
end

IO.puts("== 2. Setup: 20 teams (40 speakers), 5 judges, roll call ==")

team_lines =
  Enum.map_join(1..20, "\n", fn i ->
    "Team #{String.pad_leading("#{i}", 2, "0")} #{stamp}: Spk#{i}A #{stamp}, Spk#{i}B #{stamp}"
  end)

20 = Walk.check!("create 20 teams", Tournaments.create_teams_from_lines(actor, event_id, team_lines))

for j <- 1..5 do
  Walk.check!(
    "judge #{j}",
    EngineApi.provision_participant(actor, event_id, "Judge #{j} #{stamp}", "adjudicator")
  )
end

Walk.check!("bulk check-in (teams + judges)", Tournaments.check_in_everyone(actor, event_id))

teams = Walk.check!("list_teams (20)", EngineApi.list_teams(actor, event_id))
20 = length(teams)

# strictly ordered team totals, with the winner rotating per room/round
# so standings spread into realistic point groups
ballot_scores = fn room, n, index ->
  room["RoomTeams"]
  |> Enum.sort_by(& &1["position"])
  |> Enum.with_index()
  |> Enum.flat_map(fn {room_team, t} ->
    quality = rem(t + n + index, 4)
    base = 70 + quality * 3

    room_team["RoomSpeakers"]
    |> Enum.with_index()
    |> Enum.map(fn {speaker, i} -> {speaker["id"], base + i} end)
  end)
  |> Map.new()
end

run_prelim = fn n ->
  IO.puts("== Round #{n} (power-paired) ==")
  round = Walk.check!("round_by_sequence #{n}", Tournaments.round_by_sequence(actor, event_id, n))

  Walk.check!(
    "set motion R#{n}",
    Tournaments.set_round_motion(actor, event_id, n, "THW walkthrough motion #{n} (#{stamp})")
  )

  Walk.check!("generate_rooms R#{n}", Tournaments.generate_rooms(actor, event_id, round))
  rooms = Walk.check!("list_rooms R#{n} (5)", EngineApi.list_rooms(actor, round["id"]))
  5 = length(rooms)

  rooms =
    if n == 1 do
      # draft draw lifecycle: delete the pending draw and rebuild it
      5 = Walk.check!("delete draft draw R1", Tournaments.delete_draw(actor, round, rooms))
      5 = Walk.check!("regenerate rooms R1", Tournaments.generate_rooms(actor, event_id, round))
      rebuilt = Walk.check!("re-list rooms R1 (5)", EngineApi.list_rooms(actor, round["id"]))
      5 = length(rebuilt)
      rebuilt
    else
      rooms
    end

  Walk.check!("release draw R#{n}", Tournaments.release_draw(actor, round))
  Walk.check!("release motion R#{n}", Tournaments.release_round_motion(actor, event_id, n))

  rooms
  |> Enum.with_index(1)
  |> Enum.each(fn {room, index} ->
    scores = ballot_scores.(room, n, index)
    {:ok, rankings, speaker_scores} = Tournaments.ballot_payload(room, scores)

    Walk.check!(
      "ballot room #{room["id"]}",
      EngineApi.submit_scores(actor, room["id"], rankings, speaker_scores)
    )

    Walk.check!("confirm room #{room["id"]}", EngineApi.confirm_room(actor, room["id"]))
  end)

  Walk.check!("complete R#{n}", EngineApi.update_round(actor, round["id"], %{status: "completed"}))
end

Enum.each(1..5, run_prelim)

IO.puts("== Standings after 5 prelims (gateway builder, prelims only) ==")
entries = Walk.check!("standings", Tournaments.standings(actor, event_id))
20 = length(entries)

# 5 rounds x 5 rooms x (3+2+1+0) points fully awarded
150 = entries |> Enum.map(& &1.points) |> Enum.sum()
25 = entries |> Enum.map(& &1.firsts) |> Enum.sum()

Enum.each(Enum.take(entries, 8), fn entry ->
  IO.puts(
    "      break: #{entry.name} — #{entry.points} pts, #{entry.firsts} firsts, #{entry.seconds} seconds"
  )
end)

IO.puts("== Break: top 8 -> two semifinals ==")

%{round: semi, breaking: breaking} =
  Walk.check!("break_to_semis", Tournaments.break_to_semis(actor, event_id))

8 = length(breaking)
sf_rooms = Walk.check!("list SF rooms (2)", EngineApi.list_rooms(actor, semi["id"]))
2 = length(sf_rooms)

breaking_ids = MapSet.new(breaking, & &1.id)

sf_team_ids =
  for room <- sf_rooms, room_team <- room["RoomTeams"], do: get_in(room_team, ["Team", "id"])

true = MapSet.new(sf_team_ids) == breaking_ids

post_break_teams = Walk.check!("list_teams after break", EngineApi.list_teams(actor, event_id))
12 = Enum.count(post_break_teams, & &1["is_eliminated"])

Walk.check!("release SF draw", Tournaments.release_draw(actor, semi))

Walk.check!(
  "set SF motion",
  Tournaments.set_round_motion(actor, event_id, semi["sequence"], "THW SF motion (#{stamp})")
)

Walk.check!("release SF motion", Tournaments.release_round_motion(actor, event_id, semi["sequence"]))

# elim ballots: order each room by break rank (higher seed advances)
break_rank = breaking |> Enum.with_index(1) |> Map.new(fn {entry, rank} -> {entry.id, rank} end)

order_room = fn room ->
  room["RoomTeams"]
  |> Enum.sort_by(fn room_team -> break_rank[get_in(room_team, ["Team", "id"])] end)
  |> Enum.with_index(1)
  |> Map.new(fn {room_team, rank} -> {room_team["id"], rank} end)
end

Enum.each(sf_rooms, fn room ->
  {:ok, rankings, speaker_scores} = Tournaments.elim_ballot_payload(room, order_room.(room))

  Walk.check!(
    "SF result room #{room["id"]}",
    EngineApi.submit_scores(actor, room["id"], rankings, speaker_scores)
  )

  Walk.check!("confirm SF room #{room["id"]}", EngineApi.confirm_room(actor, room["id"]))
end)

Walk.check!("complete SF", EngineApi.update_round(actor, semi["id"], %{status: "completed"}))

IO.puts("== Grand final ==")
gf = Walk.check!("make_grand_final", Tournaments.make_grand_final(actor, event_id))
[gf_room] = Walk.check!("list GF rooms (1)", EngineApi.list_rooms(actor, gf["id"]))

# the 4 GF teams are the SF top-2s; SF losers are now eliminated
gf_ids = for room_team <- gf_room["RoomTeams"], do: get_in(room_team, ["Team", "id"])
4 = length(gf_ids)
post_sf_teams = Walk.check!("list_teams after SF", EngineApi.list_teams(actor, event_id))
16 = Enum.count(post_sf_teams, & &1["is_eliminated"])
true = Enum.all?(gf_ids, fn id -> id in breaking_ids end)

Walk.check!("release GF draw", Tournaments.release_draw(actor, gf))

{:ok, gf_rankings, gf_scores} = Tournaments.elim_ballot_payload(gf_room, order_room.(gf_room))
Walk.check!("GF result", EngineApi.submit_scores(actor, gf_room["id"], gf_rankings, gf_scores))
Walk.check!("confirm GF", EngineApi.confirm_room(actor, gf_room["id"]))
Walk.check!("complete GF", EngineApi.update_round(actor, gf["id"], %{status: "completed"}))

champion = Walk.check!("champion", Tournaments.champion(actor, event_id))
if champion == nil, do: raise("no champion resolved")

# elimination rounds never touch the (prelim) standings
entries_after = Walk.check!("standings after elims", Tournaments.standings(actor, event_id))
150 = entries_after |> Enum.map(& &1.points) |> Enum.sum()

Walk.check!(
  "complete event (full tab released)",
  EngineApi.update_event(actor, event_id, %{status: "completed"})
)

IO.puts("")
IO.puts("BP20 WALKTHROUGH COMPLETE: event #{event_id}  CHAMPION: #{champion}")
