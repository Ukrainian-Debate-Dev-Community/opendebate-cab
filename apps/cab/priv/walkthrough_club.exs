# Club session acceptance walkthrough against a LIVE engine — the
# registration-based routine session of design flow graphs 2 + 4:
# open session, 9 members self-register (8 speak, 1 judge), rooms by
# attendance via engine team auto-generate, winner pick, history.
#
#     cd platform && mix run apps/cab/priv/walkthrough_club.exs
#
# Split from walkthrough.exs so each run stays inside the engine's
# rate limit; restart the engine between runs to reset it.

Code.require_file("walk.exs", __DIR__)

alias Cab.Clubs

stamp = System.os_time(:second)

IO.puts("== 0. Host ==")
host = Walk.gateway_user!("club-host")
actor = host.node_user_id
IO.puts("  ok  host engine user id #{actor}")

IO.puts("== Club session flow (registration per flow graphs 2+4) ==")

{:ok, club} = Clubs.create_club(%{name: "Script Club #{stamp}"})

club_event =
  Walk.check!(
    "open session (org + event + round)",
    Clubs.open_session(actor, club, "Club night #{stamp}")
  )

club = Clubs.get_club(club.id)

# 8 speakers + 1 judge register THEMSELVES (1-click signup as each member)
members =
  for name <- ~w(Rita Remy Bo Bree Gale Glen Goldie Grant Judge-Jo) do
    Walk.gateway_user!("club-#{String.downcase(name)}")
  end

{speakers, [judge_user]} = Enum.split(members, 8)

for member <- speakers do
  Walk.check!(
    "signup #{member.username} (speak)",
    Clubs.signup(member.node_user_id, club_event["id"], member.username, "speaker")
  )
end

Walk.check!(
  "signup #{judge_user.username} (judge)",
  Clubs.signup(judge_user.node_user_id, club_event["id"], judge_user.username, "adjudicator")
)

{:ok, session} = Clubs.current_session(actor, club.engine_organisation_id)
:signup = session.stage
9 = length(session.participants)
IO.puts("  ok  session stage :signup with 9 self-registered participants")

1 =
  Walk.check!(
    "make rooms by attendance (auto-generated teams)",
    Clubs.make_rooms(actor, club_event["id"], session.round)
  )

{:ok, session} = Clubs.current_session(actor, club.engine_organisation_id)
:running = session.stage
[club_room] = session.rooms
IO.puts("  ok  session stage :running with 1 room (no motion yet)")

# THE JUDGE (room chair, not the host) announces this room's motion
Walk.check!(
  "judge sets their room's motion (chair privilege)",
  Clubs.set_room_motion(judge_user.node_user_id, club_room["id"], "THW let judges pick motions")
)

{:ok, session} = Clubs.current_session(actor, club.engine_organisation_id)
[club_room] = session.rooms
"THW let judges pick motions" = get_in(club_room, ["Motion", "motion_text"])
IO.puts("  ok  room now carries its own motion, set by its judge")

winner_slot = Enum.at(Enum.sort_by(club_room["RoomTeams"], & &1["position"]), 1)
Walk.check!("judge picks winner", Clubs.pick_winner(actor, club_room, winner_slot["id"]))

{:ok, session} = Clubs.current_session(actor, club.engine_organisation_id)
:closing = session.stage
IO.puts("  ok  session stage :closing after winner confirmed")
Walk.check!("finish session", Clubs.finish_session(actor, club_event["id"], session.round))

{:ok, history} = Clubs.club_history(actor, club.engine_organisation_id)
%{"winner" => club_winner} = Enum.find(history, &(&1["id"] == club_event["id"]))
true = is_binary(club_winner)
IO.puts("      club winner: #{club_winner}")

IO.puts("")
IO.puts("CLUB WALKTHROUGH COMPLETE: club #{club.id} event #{club_event["id"]} winner=#{club_winner}")
