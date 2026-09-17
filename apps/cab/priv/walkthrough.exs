# Full acceptance walkthrough against a LIVE engine.
#
#     cd platform && mix run apps/cab/priv/walkthrough.exs
#
# Requires: the Node engine running on ENGINE_URL (default
# http://localhost:3100) with the shared ENGINE_JWT_SECRET, and the
# gateway dev database. Exercises every Cab.EngineApi call used by the
# LiveViews: tournament (8 teams, 2 judges, 3 rounds + final,
# champion) and the club session flow.

alias Cab.{Accounts, Clubs, EngineApi, Tournaments, Repo}
alias Cab.Accounts.User

defmodule Walk do
  def check!(label, result) do
    case result do
      {:ok, value} ->
        IO.puts("  ok  #{label}")
        value

      :ok ->
        IO.puts("  ok  #{label}")
        :ok

      {:error, reason} ->
        IO.puts("  FAIL #{label}: #{inspect(reason)}")
        raise "walkthrough failed at: #{label}"

      other ->
        IO.puts("  ok  #{label} -> #{inspect(other)}")
        other
    end
  end

  def gateway_user!(username) do
    user =
      Repo.get_by(User, username: username) ||
        Repo.insert!(User.changeset(%User{}, %{username: username}))

    user = Accounts.ensure_node_user(user)

    if user.node_user_id == nil do
      raise "could not provision engine user for #{username} — is the engine up?"
    end

    user
  end
end


stamp = System.os_time(:second)

IO.puts("== 0. Actors ==")
td = Walk.gateway_user!("td-script")
helper = Walk.gateway_user!("td-helper")
actor = td.node_user_id
IO.puts("  ok  TD engine user id #{actor}; helper engine user id #{helper.node_user_id}")

IO.puts("== 1. Dashboard: public list + create tournament ==")
Walk.check!("list_public_events", EngineApi.list_public_events())

%{"event" => event, "org" => org} =
  Walk.check!("create_tournament", EngineApi.create_tournament(actor, "Cab Open #{stamp}"))

event_id = event["id"]

for n <- 1..3 do
  Walk.check!("create_round #{n}", EngineApi.create_round(actor, event_id, "Round #{n}", n))
end

Walk.check!("get_event", EngineApi.get_event(actor, event_id))

IO.puts("== 2. Setup: 8 teams (16 shadow speakers), 2 judges, organizer role ==")

team_lines =
  """
  Alpha: Alice #{stamp}, Aaron #{stamp}
  Bravo: Bella #{stamp}, Bruno #{stamp}
  Charlie: Cara #{stamp}, Carl #{stamp}
  Delta: Dana #{stamp}, Dino #{stamp}
  Echo: Elle #{stamp}, Enzo #{stamp}
  Foxtrot: Fay #{stamp}, Finn #{stamp}
  Golf: Gia #{stamp}, Gus #{stamp}
  Hotel: Hana #{stamp}, Hugo #{stamp}
  """

8 = Walk.check!("create_teams_from_lines (8)", Tournaments.create_teams_from_lines(actor, event_id, team_lines))

_judge1 = Walk.check!("provision judge 1", EngineApi.provision_participant(actor, event_id, "Judge One", "adjudicator"))
_judge2 = Walk.check!("provision judge 2", EngineApi.provision_participant(actor, event_id, "Judge Two", "adjudicator"))

Walk.check!("add_organizer (tab)", EngineApi.add_organizer(actor, event_id, helper.node_user_id, "tab"))
organizers = Walk.check!("list_organizers", EngineApi.list_organizers(actor, event_id))
true = Enum.any?(organizers, &(&1["user_id"] == helper.node_user_id and &1["role"] == "tab"))

teams = Walk.check!("list_teams (8)", EngineApi.list_teams(actor, event_id))
8 = length(teams)
participants = Walk.check!("list_participants (18)", EngineApi.list_participants(actor, event_id))
18 = length(participants)

run_round = fn n, first? ->
  IO.puts("== Round #{n} ==")
  round = Walk.check!("round_by_sequence #{n}", Tournaments.round_by_sequence(actor, event_id, n))

  if first? do
    teams_ci = Walk.check!("teams_with_checkin", Tournaments.teams_with_checkin(actor, event_id))

    for team <- teams_ci do
      Walk.check!("check in #{team["name"]}", Tournaments.set_team_checkin(actor, event_id, team, true))
    end
  end

  Walk.check!("set motion R#{n}", Tournaments.set_round_motion(actor, event_id, n, "THW test motion #{n} (#{stamp})"))
  Walk.check!("generate_rooms R#{n}", Tournaments.generate_rooms(actor, event_id, round))
  rooms = Walk.check!("list_rooms R#{n} (2)", EngineApi.list_rooms(actor, round["id"]))
  2 = length(rooms)

  if first? do
    [room_a, room_b | _] = rooms
    slot_a = hd(Enum.sort_by(room_a["RoomTeams"], & &1["position"]))
    slot_b = hd(Enum.sort_by(room_b["RoomTeams"], & &1["position"]))
    Walk.check!("swap_teams across rooms", EngineApi.swap_teams(actor, round["id"], slot_a["id"], slot_b["id"]))
    Walk.check!("swap_teams back", EngineApi.swap_teams(actor, round["id"], slot_b["id"], slot_a["id"]))
  end

  Walk.check!("release motion R#{n}", Tournaments.release_round_motion(actor, event_id, n))

  rooms = Walk.check!("re-list rooms R#{n}", EngineApi.list_rooms(actor, round["id"]))

  Enum.with_index(rooms, 1)
  |> Enum.each(fn {room, index} ->
    speakers = for rt <- room["RoomTeams"], sp <- rt["RoomSpeakers"], do: sp["id"]

    scores =
      speakers
      |> Enum.with_index()
      |> Map.new(fn {id, i} -> {id, 70 + rem(i * 3 + n + index, 11)} end)

    {:ok, rankings, speaker_scores} = Tournaments.ballot_payload(room, scores)
    Walk.check!("submit ballot room #{room["id"]}", EngineApi.submit_scores(actor, room["id"], rankings, speaker_scores))

    if first? and index == 1 do
      Walk.check!("reopen room #{room["id"]}", EngineApi.reopen_room(actor, room["id"]))
      Walk.check!("resubmit ballot room #{room["id"]}", EngineApi.submit_scores(actor, room["id"], rankings, speaker_scores))
      Walk.check!("confirm room #{room["id"]}", EngineApi.confirm_room(actor, room["id"]))
      Walk.check!("unconfirm room #{room["id"]}", EngineApi.unconfirm_room(actor, room["id"]))
      Walk.check!("re-confirm room #{room["id"]}", EngineApi.confirm_room(actor, room["id"]))
    else
      Walk.check!("confirm room #{room["id"]}", EngineApi.confirm_room(actor, room["id"]))
    end
  end)

  Walk.check!("complete round #{n}", EngineApi.update_round(actor, round["id"], %{status: "completed"}))
end

run_round.(1, true)
run_round.(2, false)
run_round.(3, false)

IO.puts("== Standings after prelims ==")
standings = Walk.check!("team_standings", EngineApi.team_standings(actor, event_id))
Walk.check!("speaker_standings", EngineApi.speaker_standings(actor, event_id))

Enum.each(Enum.take(standings, 4), fn t ->
  IO.puts("      break: #{t["name"]} (#{t["total_points"]} pts)")
end)

IO.puts("== Final ==")
final = Walk.check!("break_to_final", Tournaments.break_to_final(actor, event_id))
[final_room] = Walk.check!("list final rooms (1)", EngineApi.list_rooms(actor, final["id"]))

bottom_ids = standings |> Enum.drop(4) |> Enum.map(& &1["id"])
Walk.check!("eliminate bottom 4 teams", EngineApi.eliminate_teams(actor, event_id, bottom_ids, true))

final_speakers = for rt <- final_room["RoomTeams"], sp <- rt["RoomSpeakers"], do: sp["id"]

final_scores =
  final_speakers |> Enum.with_index() |> Map.new(fn {id, i} -> {id, 80 + rem(i * 5, 15)} end)

{:ok, final_rankings, final_speaker_scores} = Tournaments.ballot_payload(final_room, final_scores)

Walk.check!("submit final ballot", EngineApi.submit_scores(actor, final_room["id"], final_rankings, final_speaker_scores))
Walk.check!("confirm final", EngineApi.confirm_room(actor, final_room["id"]))
Walk.check!("complete final round", EngineApi.update_round(actor, final["id"], %{status: "completed"}))

champion = Walk.check!("champion", Tournaments.champion(actor, event_id))
IO.puts("      CHAMPION: #{champion}")
if champion == nil, do: raise("no champion resolved")

Walk.check!("mark event completed", EngineApi.update_event(actor, event_id, %{status: "completed"}))

IO.puts("== Club session flow ==")

{:ok, club} = Clubs.create_club(%{name: "Script Club #{stamp}"})

club_org = Walk.check!("create club organisation", EngineApi.create_organisation(actor, "#{club.name} (club)"))
Walk.check!("club add_owner (helper co-owner)", EngineApi.add_owner(actor, club_org["id"], helper.node_user_id))
{:ok, club} = Clubs.update_club(club, %{engine_organisation_id: club_org["id"]})

club_event = Walk.check!("create club event", EngineApi.create_event(actor, club.engine_organisation_id, "Club night #{stamp}"))
club_round = Walk.check!("create club round", EngineApi.create_round(actor, club_event["id"], "Club round", 1))

club_lines =
  """
  Reds: Rita #{stamp}, Remy #{stamp}
  Blues: Bo #{stamp}, Bree #{stamp}
  Greens: Gale #{stamp}, Glen #{stamp}
  Golds: Goldie #{stamp}, Grant #{stamp}
  """

4 = Walk.check!("club teams", Tournaments.create_teams_from_lines(actor, club_event["id"], club_lines))
club_judge = Walk.check!("club judge", EngineApi.provision_participant(actor, club_event["id"], "Club Judge", "adjudicator"))
club_teams = Walk.check!("club list_teams", EngineApi.list_teams(actor, club_event["id"]))

club_slots =
  club_teams |> Enum.with_index(1) |> Enum.map(fn {t, i} -> %{team_id: t["id"], position: i} end)

Walk.check!(
  "club create_room",
  EngineApi.create_room(actor, club_round["id"], club_slots, [
    %{participant_id: club_judge["id"], role: "chair"}
  ])
)

[club_room] = Walk.check!("club list_rooms (1)", EngineApi.list_rooms(actor, club_round["id"]))

winner_slot = Enum.at(Enum.sort_by(club_room["RoomTeams"], & &1["position"]), 1)
{:ok, w_rankings, w_scores} = Tournaments.winner_ballot_payload(club_room, winner_slot["id"])

Walk.check!("club winner ballot", EngineApi.submit_scores(actor, club_room["id"], w_rankings, w_scores))
Walk.check!("club confirm", EngineApi.confirm_room(actor, club_room["id"]))
Walk.check!("club round completed", EngineApi.update_round(actor, club_round["id"], %{status: "completed"}))
Walk.check!("club event completed", EngineApi.update_event(actor, club_event["id"], %{status: "completed"}))

history = Walk.check!("club history", EngineApi.list_organisation_events(actor, club.engine_organisation_id))
true = Enum.any?(history, &(&1["id"] == club_event["id"] and &1["status"] == "completed"))
IO.puts("      club winner: #{get_in(winner_slot, ["Team", "name"])}")

IO.puts("")
IO.puts("WALKTHROUGH COMPLETE: tournament #{event_id} (org #{org["id"]}) champion=#{champion}; club event #{club_event["id"]}")
