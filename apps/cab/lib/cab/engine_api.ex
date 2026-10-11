defmodule Cab.EngineApi do
  @moduledoc """
  Typed, thin wrappers over `Core.Engine` for every engine call the gateway  needs. Every function takes the acting engine user id (`actor` =
  `user.node_user_id`) first and returns `{:ok, data}` or
  `{:error, message}` with a human-readable message suitable for
  inline display.

  ## ENGINE AUDIT (engine/, branch feat/engine-light, 2026-09)

  Base URL `/api`, auth `Authorization: Bearer <HS256 JWT {id, isAdmin}>`.
  Responses: `{"status":"success","data"|... }`; errors
  `{"status":"fail"|"error","message": "..."}` with 4xx/5xx.

  ### Authorisation model (src/middleware/authMiddleware.js)
  - `restrictToAdmin` - `isAdmin` claim only.
  - `restrictToOwnOrg` - admin OR Owner of the event's organisation OR
    Organizer of the event (`hasEventPrivilege`). Org-scoped routes
    (no event): owner of that org. Format routes: admin only.
  - `restrictToChair` - room chair, WITH FALL-THROUGH to
    `hasEventPrivilege` (admin/owner/organiser). => Owner/organiser CAN
    submit and edit scores for any room. NO ENGINE PATCH NEEDED.
  - Feedback: `POST /rooms/:roomId/feedback` - any authenticated user.

  ### Users
  - `POST /users/register` {username,password} -> 201 {token,data:{id}}
    (public; used by Core.Engine.provision_user)
  - `POST /users/login` {username,password} -> {token}

  ### Organisations
  - `POST /organisations` {name, owner_id, type?} - ADMIN ONLY;
    creates the Owner row for owner_id too -> 201 data{id,name}
  - `POST /organisations/:orgId/owners` {targetUserId} - owner-of-org
    or admin -> 201
  - `GET /organisations`, `GET /organisations/:id` - any authed user

  ### Events
  - `GET /events` - PUBLIC list (paginated, default 20; ?status=&from=&to=)
    data: [{id,name,start_date,end_date,status,is_ranked,Organisation}]
  - `POST /events/:organisationId` {name,start_date,end_date,is_ranked}
    - owner of org -> 201 data (event, status "scheduled")
  - `GET /events/:eventId` - any authed
  - `PUT /events/:eventId` {name,status,...} - status in
    scheduled|in_progress|completed - owner/organiser
  - `GET /events/organisation/:organisationId` - any authed
  - `GET /events/:eventId/access` -> data{isPrivileged}
  - `DELETE /events/:eventId` - owner/organiser; archives (soft) by
    default, `?hard=true` is admin-only. Archived events drop out of
    all paranoid listings.

  ### Organizers (event roles)
  - `GET /events/:eventId/organizers`
  - `POST /events/:eventId/organizers` {targetUserId, role} - role in
    organiser|tab|adjcore (default organiser) - owner/organiser
  - `PATCH /events/:eventId/organizers/:targetUserId` {role}
  - `DELETE /events/:eventId/organizers/:targetUserId`

  ### Participants
  - `GET /events/:eventId/participants` -> data [{id,user_id,
    display_name,role,checked_in,is_eliminated}]
  - `POST /events/:eventId/participants` {user_id?,display_name,role}
    - role speaker|adjudicator. Privileged callers may register other
    users or guests (guest gets raw_claim_token). -> 201 data{id,...}
  - `PATCH /events/:eventId/participants/:pid/check-in` {checked_in}
    - organiser or self
  - `PATCH /events/:eventId/check-ins` {status, participant_ids[]}
    - bulk, owner/organiser
  - `PATCH /events/:eventId/eliminations` {status, team_ids[]?,
    participant_ids[]?} - owner/organiser (adjudicators not eliminable)
  - `DELETE /events/:eventId/participants/:pid` - owner/organiser;
    archives. 409 while a TeamMember row or a RoomAdjudicator seat
    exists for the participant - NOTE these checks do not join the
    (paranoid) Team/Room, so a participant who was EVER paired stays
    unremovable even after their team/room was archived. Removal is
    therefore a sign-up-stage operation.

  ### Teams
  - `GET /events/:eventId/teams` -> data [{id,name,is_temporary,
    is_swing,is_eliminated,speakers:[{participant_id,name,user_id}]}]
  - `POST /events/:eventId/teams` {name, participant_ids[], is_swing?}
    - duplicates in participant_ids = iron-person; one permanent team
    per participant per event -> 201 data{id,...}
  - `PUT /events/:eventId/teams/:teamId` {name?,participant_ids?,is_swing?}
  - `GET /events/:eventId/teams/auto-generate?format_id=` - PROPOSES
    random teams from free (checked-in) speakers; does NOT create rooms.

  ### Rounds
  - `GET /events/:eventId/rounds` -> data [{id,name,sequence,status,
    is_hidden}] (status draft|in_progress|completed)
  - `POST /events/:eventId/rounds` {name, sequence, is_hidden?} -> 201
  - `PUT /rounds/:roundId` {name?,sequence?,status?,is_hidden?}
  - `PATCH /events/:eventId/rounds/release-all` - un-hides all rounds

  ### Teams vs rooms lifecycle (verified for the rebuild loop)
  - POST rooms accepts `{name, participant_ids, position}` entries
    which create TEMPORARY teams inline; `DELETE /rooms/:roomId`
    purges those temporary teams together with the (pending) room.
  - Temporary teams never lock speakers: both auto-generate's
    free-speaker check and createTeam's one-permanent-team-per-event
    rule only count `is_temporary: false` teams, joined through the
    paranoid Team model (archived teams don't count either).
  - The team-name-unique-per-event index is partial
    (`where archived_at is null`), so names can be reused after a
    rebuild. => club pairing uses inline temporary teams.

  ### Rooms (no auto-generate endpoint - rooms are created explicitly)
  - `GET /rounds/:roundId/rooms` -> data [{id,status,Format,
    RoomAdjudicators:[{id,role,EventParticipant}],
    RoomTeams:[{id,position,rank,Team,RoomSpeakers:[{id,rank,
    EventParticipant}]}]}]
  - `POST /rounds/:roundId/rooms` {format_id, motion_id?, teams:
    [{team_id,position}|{name,participant_ids,position}], adjudicators:
    [{participant_id, role: chair|panelist|trainee}]} - exactly
    format.teams_per_room teams, positions a permutation of 1..N, at
    least one chair; adjudicator must have role "adjudicator" and not
    already sit in this round; speakers can't be double-booked.
    Room statuses: pending -> judging -> completed -> confirmed | void.
  - `PATCH /rounds/:roundId/rooms/swap-teams` {room_team_id_a,
    room_team_id_b} - both rooms must be 'pending', same format.
  - `POST /rooms/:roomId/motion` {motion_text, infoslide?} - the
    room's CHAIR (owner/organiser fall-through) sets this room's
    motion while pending/judging: creates a released event motion and
    attaches it atomically. Rooms of one round may carry different
    motions (club sessions). Room listing includes each room's Motion.
  - `DELETE /rooms/:roomId` - not while judging/completed/confirmed.

  ### Motions (event-scoped; rooms reference motion_id optionally)
  - `GET /events/:eventId/motions` - unreleased text masked for
    unprivileged viewers; 404 when none exist
  - `POST /events/:eventId/motions` {motion_text, infoslide?,
    is_released?} -> 201
  - `PUT /events/:eventId/motions/:motionId` {motion_text?, infoslide?,
    is_released?} - releasing = is_released: true

  ### Scores / ballots (all allowed for owner/organiser via fall-through)
  - `POST /rooms/:roomId/scores` {teamRankings:[{room_team_id,rank}],
    speakerScores:[{room_speaker_id,score}]} - ranks a permutation of
    1..teams_per_room, exactly teams_per_room*speakers_per_team scores,
    each within format score_min..score_max (BP: 50..100). Attributed
    to the room's chair. Room -> 'completed'. A completed room accepts
    resubmission as an atomic replace of the previous ballot (it stays
    completed); only 'confirmed' and 'void' reject submission, so
    editing a locked ballot = unconfirm + resubmit. Nothing ever wipes
    a submitted result.
  - `PATCH /rooms/:roomId/confirm` - completed -> confirmed (locks)
  - `PATCH /rooms/:roomId/unconfirm` - confirmed -> completed

  ### Standings
  - `GET /events/:eventId/standings/teams` - raw per-room ranks
  - `GET /events/:eventId/standings/calculated/teams` -> sorted
    [{id,name,total_points}] where points = sum(N - rank); swing teams
    excluded; hidden rounds included only for privileged viewers.
  - `GET /events/:eventId/standings/calculated/speakers` -> sorted
    [{id,name,total_points}], points = sum(score * (1+(N-rank)*0.1))

  ### Formats
  - `GET /formats` - seeded: id 1 = British Parliamentary (BP),
    4 teams/room, 2 speakers/team, scores 50..100. Writes admin-only.

  ### Conclusion
  Everything the gateway needs exists. The one gap-shaped item - organiser
  score submission - is already covered by `restrictToChair`'s
  owner/organiser fall-through, so no engine patch was required.
  Room "auto-generate" does not exist; the gateway pairs teams itself
  and POSTs explicit rooms. Organisation creation is admin-only; the
  gateway mints an isAdmin token (shared secret) to create the org,
  then adds the acting user as owner for full control.
  """

  require Logger
  use Gettext, backend: CabWeb.Gettext

  alias Core.Engine

  @bp_format_id 1

  # ---------------------------------------------------------------
  # Public
  # ---------------------------------------------------------------

  @doc "The engine's public event list (the uadebate portal's tournament feed)."
  def list_public_events(params \\ []) do
    Engine.public_get("/api/events", params: params) |> unwrap()
  end

  # ---------------------------------------------------------------
  # Organisations (org creation is admin-only in the engine)
  # ---------------------------------------------------------------

  @doc """
  Creates an organisation (admin-only in the engine, so this call uses
  an isAdmin token). The engine requires an initial owner; it defaults
  to the actor, giving them full control.
  """
  def create_organisation(actor, name, owner_id \\ nil) do
    Engine.post(actor, "/api/organisations", %{name: name, owner_id: owner_id || actor},
      admin: true
    )
    |> unwrap()
  end

  @doc "Renames an organisation (its owner may)."
  def rename_organisation(actor, org_id, name) do
    Engine.put(actor, "/api/organisations/#{org_id}", %{name: name}) |> unwrap()
  end

  def add_owner(actor, org_id, target_user_id) do
    Engine.post(actor, "/api/organisations/#{org_id}/owners", %{targetUserId: target_user_id},
      admin: true
    )
    |> unwrap()
  end

  @doc "Removes an owner of an organisation (admin-only; never the last owner)."
  def remove_owner(actor, org_id, target_user_id) do
    Engine.delete(actor, "/api/organisations/#{org_id}/owners/#{target_user_id}", admin: true)
    |> unwrap()
  end

  @doc """
  Moves every participation of `source_id` onto `target_id` and
  anonymises the emptied source (admin-only in the engine). Refused
  with a message when both hold a registration in the same event.
  """
  def merge_users(actor, source_id, target_id, display_name) do
    Engine.post(
      actor,
      "/api/admins/merge",
      %{sourceUserId: source_id, targetUserId: target_id, displayName: display_name},
      admin: true
    )
    |> unwrap()
  end

  def list_organisation_events(actor, org_id) do
    Engine.get(actor, "/api/events/organisation/#{org_id}") |> unwrap()
  end

  # ---------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------

  def create_event(actor, org_id, name, attrs \\ %{}) do
    Engine.post(actor, "/api/events/#{org_id}", Map.merge(%{name: name}, attrs)) |> unwrap()
  end

  def get_event(actor, event_id) do
    Engine.get(actor, "/api/events/#{event_id}") |> unwrap()
  end

  def update_event(actor, event_id, attrs) do
    Engine.put(actor, "/api/events/#{event_id}", attrs) |> unwrap()
  end

  @doc "Archives an event (soft delete; owner/organiser)."
  def delete_event(actor, event_id) do
    Engine.delete(actor, "/api/events/#{event_id}") |> unwrap()
  end

  # ---------------------------------------------------------------
  # Rounds
  # ---------------------------------------------------------------

  def create_round(actor, event_id, name, sequence) do
    Engine.post(actor, "/api/events/#{event_id}/rounds", %{name: name, sequence: sequence})
    |> unwrap()
  end

  def list_rounds(actor, event_id) do
    Engine.get(actor, "/api/events/#{event_id}/rounds") |> unwrap()
  end

  def update_round(actor, round_id, attrs) do
    Engine.put(actor, "/api/rounds/#{round_id}", attrs) |> unwrap()
  end

  # ---------------------------------------------------------------
  # Participants
  # ---------------------------------------------------------------

  def add_participant(actor, event_id, display_name, role, user_id \\ nil) do
    body = %{display_name: display_name, role: role}
    body = if user_id, do: Map.put(body, :user_id, user_id), else: body
    Engine.post(actor, "/api/events/#{event_id}/participants", body) |> unwrap()
  end

  def update_participant(actor, event_id, participant_id, attrs) do
    Engine.put(actor, "/api/events/#{event_id}/participants/#{participant_id}", attrs)
    |> unwrap()
  end

  @doc "The invited user redeems the one-time claim token: the participant becomes theirs."
  def claim_participant(actor, participant_id, claim_token) do
    Engine.post(actor, "/api/users/claim-participant/#{participant_id}", %{
      claim_token: claim_token
    })
    |> unwrap()
  end

  def list_participants(actor, event_id) do
    Engine.get(actor, "/api/events/#{event_id}/participants") |> unwrap()
  end

  @doc """
  Removes (archives) an event participant. Owner/organiser-only in
  the engine; 409 while the participant is attached to a team or
  seated as a room adjudicator - see the module audit.
  """
  def delete_participant(actor, event_id, participant_id) do
    Engine.delete(actor, "/api/events/#{event_id}/participants/#{participant_id}") |> unwrap()
  end

  # ---------------------------------------------------------------
  # Rooms
  # ---------------------------------------------------------------

  @doc """
  Creates a room. `teams` = [%{team_id: id, position: 1..N}],
  `adjudicators` = [%{participant_id: id, role: "chair"}].
  """
  def create_room(actor, round_id, teams, adjudicators, opts \\ []) do
    body = %{
      format_id: Keyword.get(opts, :format_id, @bp_format_id),
      teams: teams,
      adjudicators: adjudicators
    }

    body =
      case Keyword.get(opts, :motion_id) do
        nil -> body
        motion_id -> Map.put(body, :motion_id, motion_id)
      end

    Engine.post(actor, "/api/rounds/#{round_id}/rooms", body) |> unwrap()
  end

  def list_rooms(actor, round_id) do
    Engine.get(actor, "/api/rounds/#{round_id}/rooms") |> unwrap()
  end

  @doc """
  Deletes a room (engine refuses while judging/completed/confirmed -
  i.e. only pending rooms go). Used by the delete-draw rebuild loop.
  """
  def delete_room(actor, room_id) do
    Engine.delete(actor, "/api/rooms/#{room_id}") |> unwrap()
  end

  @doc """
  Sets THIS room's motion as its judge (chair; owner/organiser
  fall-through). The engine creates a released event motion and
  attaches it to the room atomically.
  """
  def set_room_motion(actor, room_id, motion_text, attrs \\ %{}) do
    Engine.post(
      actor,
      "/api/rooms/#{room_id}/motion",
      Map.merge(%{motion_text: motion_text}, attrs)
    )
    |> unwrap()
  end

  @doc "Sets or clears (nil) when the room's prep ends (chair, or owner/organiser)."
  def set_room_prep(actor, room_id, prep_ends_at) do
    Engine.patch(actor, "/api/rooms/#{room_id}/prep", %{prep_ends_at: prep_ends_at})
    |> unwrap()
  end

  # ---------------------------------------------------------------
  # Scores / ballots
  # ---------------------------------------------------------------

  @doc """
  Submits a full ballot. `team_rankings` = [%{room_team_id: id, rank: 1..N}],
  `speaker_scores` = [%{room_speaker_id: id, score: number}].
  """
  def submit_scores(actor, room_id, team_rankings, speaker_scores) do
    Engine.post(actor, "/api/rooms/#{room_id}/scores", %{
      teamRankings: team_rankings,
      speakerScores: speaker_scores
    })
    |> unwrap()
  end

  def confirm_room(actor, room_id) do
    Engine.patch(actor, "/api/rooms/#{room_id}/confirm", %{}) |> unwrap()
  end

  def unconfirm_room(actor, room_id) do
    Engine.patch(actor, "/api/rooms/#{room_id}/unconfirm", %{}) |> unwrap()
  end

  # ---------------------------------------------------------------
  # Users (self-scoped reads run as that user's actor)
  # ---------------------------------------------------------------

  def user_stats(actor, user_id) do
    Engine.get(actor, "/api/users/#{user_id}/stats") |> unwrap()
  end

  def user_history(actor, limit \\ 200) do
    Engine.get(actor, "/api/users/history?limit=#{limit}") |> unwrap()
  end

  def user_schedule(actor) do
    Engine.get(actor, "/api/users/schedule") |> unwrap()
  end

  # ---------------------------------------------------------------
  # Standings
  # ---------------------------------------------------------------

  def team_standings(actor, event_id) do
    Engine.get(actor, "/api/events/#{event_id}/standings/calculated/teams") |> unwrap()
  end

  def speaker_standings(actor, event_id) do
    Engine.get(actor, "/api/events/#{event_id}/standings/calculated/speakers") |> unwrap()
  end

  def adjudicator_stats(actor, event_id) do
    Engine.get(actor, "/api/events/#{event_id}/stats/adjudicators") |> unwrap()
  end

  @doc "Adjudicator statistics with `base` counted as one extra feedback vote."
  def adjudicator_stats(actor, event_id, base) do
    Engine.get(actor, "/api/events/#{event_id}/stats/adjudicators", params: [base: base])
    |> unwrap()
  end

  # ---------------------------------------------------------------
  # Feedback on adjudicators
  # ---------------------------------------------------------------

  @doc "The event's feedback form: its questions, in order."
  def feedback_questions(actor, event_id) do
    Engine.get(actor, "/api/events/#{event_id}/feedback-questions") |> unwrap()
  end

  @doc "Adds a question to the event's feedback form (owner/organiser)."
  def create_feedback_question(actor, event_id, attrs) do
    Engine.post(actor, "/api/events/#{event_id}/feedback-questions", attrs) |> unwrap()
  end

  @doc """
  Sends feedback on a room's adjudicator: `%{adjudicator_id,
  issuer_team_id, comment, answers: [%{key, value}]}`.
  """
  def submit_feedback(actor, room_id, body) do
    Engine.post(actor, "/api/rooms/#{room_id}/feedback", body) |> unwrap()
  end

  @doc "Every feedback of the event with its answers and score (owner/organiser)."
  def event_feedback(actor, event_id) do
    Engine.get(actor, "/api/events/#{event_id}/feedback") |> unwrap()
  end

  # ---------------------------------------------------------------
  # Response normalisation
  # ---------------------------------------------------------------

  defp unwrap({:ok, %Req.Response{status: status, body: body}}) when status in 200..299 do
    case body do
      %{"data" => data} -> {:ok, data}
      other -> {:ok, other}
    end
  end

  defp unwrap({:ok, %Req.Response{status: status, body: body}}) do
    message =
      case body do
        %{"message" => message} when is_binary(message) ->
          message

        other ->
          Logger.warning("engine returned #{status}: #{inspect(other)}")
          dgettext("errors", "Something went wrong, try again.")
      end

    {:error, message}
  end

  defp unwrap({:error, exception}) do
    Logger.warning("engine unreachable: #{Exception.message(exception)}")
    {:error, dgettext("errors", "Something went wrong, try again.")}
  end
end
