defmodule CabWeb.Tour.Pages do
  @moduledoc """
  The pages a tour shows: each frame is one of cab's real page
  templates with the assigns its controller or LiveView would give it,
  built from `CabWeb.Tour.Demo` instead of the engine and the database.
  `frame/1` returns `{html module, template, assigns}`, or nil for an
  unknown frame.
  """
  use Gettext, backend: CabWeb.Gettext

  alias CabWeb.Tour.Demo

  @frames ~w(clubs club-visitor join me-pending me-register me-register-form me-registered
             me-now me-result me-feedback-sent me-figures me-chair me-ballot 
             me-on-me guest-hub owner-club owner-members owner-form owner-registration
             owner-rooms owner-debates owner-finished results)

  @doc "Every frame's key."
  def frames, do: @frames

  @doc "The frame's template and assigns."
  def frame(key) when key in @frames, do: build(key)
  def frame(_key), do: nil

  # ---------------------------------------------------------------
  # The club, as a visitor or a member sees it
  # ---------------------------------------------------------------

  defp build("clubs") do
    club = Demo.club()

    {CabWeb.PageHTML, :home,
     base(Demo.newcomer(), nil, :public, %{
       clubs: [club],
       member_counts: %{club.id => length(Demo.members())},
       tonight: %{club.id => {Demo.session(:signup), :signup, 0}},
       open_club: nil,
       invitations: 0,
       page_title: gettext("Clubs")
     })}
  end

  # the club page as Mark sees it before he joins
  defp build("club-visitor") do
    user = Demo.newcomer()
    session = Demo.session(:signup)
    {_kind, fields, _values} = {:account, Cab.Clubs.member_fields(session.club), %{}}

    {CabWeb.ClubPublicHTML, :show,
     base(user, Demo.club(), :public, %{
       recent: archive(),
       mine: %{},
       members: Demo.members(),
       registration: registration(session, %{kind: :account, fields: fields}),
       page_title: Demo.club().name
     })}
  end

  defp build("join") do
    club = Demo.club()

    {CabWeb.ClubPublicHTML, :join,
     base(Demo.newcomer(), club, :public, %{
       fields: Cab.Clubs.member_fields(club),
       answers: %{},
       errors: %{},
       page_title: gettext("%{club} — Join", club: club.name)
     })}
  end

  # ---------------------------------------------------------------
  # My page
  # ---------------------------------------------------------------

  defp build("me-pending"),
    do: me(Demo.newcomer(), :signup, membership: "pending", registered: false, newcomer: true)

  defp build("me-register"), do: me(Demo.speaker(), :signup, registered: false)

  defp build("me-register-form"),
    do: me(Demo.speaker(), :signup, registered: false, registering: true)

  defp build("me-registered"), do: me(Demo.speaker(), :signup, registered: true)
  defp build("me-now"), do: me(Demo.speaker(), :running, room: :judging)
  defp build("me-result"), do: me(Demo.speaker(), :running, room: :completed)

  defp build("me-feedback-sent"),
    do: me(Demo.speaker(), :running, room: :completed, feedback_sent: true)

  defp build("me-figures"), do: me(Demo.speaker(), :none, figures: true)
  defp build("me-chair"), do: me(Demo.chair(), :running, room: :pending)
  defp build("me-ballot"), do: me(Demo.chair(), :running, room: :judging)
  defp build("me-on-me"), do: me(Demo.chair(), :none, figures: true, on_me: true)
  defp build("guest-hub"), do: me(Demo.guest(), :running, room: :judging, guest: true)

  # ---------------------------------------------------------------
  # The head's pages
  # ---------------------------------------------------------------

  defp build("owner-club") do
    club = Demo.club()

    {CabWeb.OwnerHTML, :club,
     base(Demo.head(), club, :owner, %{
       profile: club,
       profile_errors: %{},
       opening: %{values: %{}, errors: %{}},
       archive: archive(),
       live: Demo.session(:signup),
       formats: Cab.Format.all(),
       page_title: gettext("%{club} — Edit", club: club.name)
     })}
  end

  defp build("owner-members") do
    club = Demo.club()

    {CabWeb.OwnerHTML, :members,
     base(Demo.head(), club, :owner, %{
       members: Demo.members(),
       join_requests: Demo.join_requests(),
       page_title: gettext("%{club} — Members", club: club.name)
     })}
  end

  defp build("owner-form") do
    club = Demo.club()

    {CabWeb.OwnerHTML, :guest_form,
     base(Demo.head(), club, :owner, %{
       definition: Cab.Clubs.guest_form(club),
       editing: nil,
       values: %{},
       errors: %{},
       page_title: gettext("%{club} - Registration form", club: club.name)
     })}
  end

  defp build("owner-registration"), do: owner(:signup, :registration)
  defp build("owner-rooms"), do: owner(:closed, :rooms)
  defp build("owner-debates"), do: owner(:running, :debates)
  defp build("owner-finished"), do: owner(:done, :finished)

  defp build("results") do
    session = Demo.session(:done)
    state = Demo.state(:done)

    {CabWeb.SessionPageHTML, :show,
     base(nil, Demo.club(), :public, %{
       session: session,
       state: state,
       winners: Cab.Sessions.winners_by_room(state.rooms),
       on_me: [],
       my_average: nil,
       my_signup: nil,
       guest: false,
       hub: nil,
       my_room_id: nil,
       short_url: short_url(),
       page_title: "#{Demo.club().name} — #{state.event["name"]}"
     })}
  end

  # ---------------------------------------------------------------
  # Builders
  # ---------------------------------------------------------------

  defp base(user, club, role, assigns) do
    Map.merge(
      %{
        flash: %{},
        current_user: user,
        club: club,
        club_role: role,
        nav_session: club && Demo.session(:signup)
      },
      assigns
    )
  end

  # what a short link looks like; the tour never makes one
  defp short_url, do: CabWeb.Endpoint.url() <> "/rvsd7k"

  defp archive do
    for session <- [Demo.session(:signup) | Demo.past_sessions()] do
      %{
        session_uuid: session.uuid,
        name: session.name,
        date: session.scheduled_at,
        status: if(session.finished_at, do: :finished, else: :open),
        winner: session.winner_name
      }
    end
  end

  defp registration(session, fields) do
    Map.merge(
      %{
        session: session,
        kind: nil,
        fields: [],
        values: %{},
        name: nil,
        errors: %{},
        signup: nil,
        done: nil,
        choices: [],
        notice: nil
      },
      fields
    )
  end

  # My page for `user` with tonight's session at `stage` (:none: no
  # session tonight)
  defp me(user, stage, opts) do
    guest? = Keyword.get(opts, :guest, false)
    session = if stage != :none, do: Demo.session(stage)
    state = session && Demo.state(stage, Keyword.get(opts, :room, :judging))
    format = Cab.Format.of(Demo.session(:signup))
    # a newcomer (Mark, before his first session) has no figures yet
    newcomer? = Keyword.get(opts, :newcomer, false)
    figures? = not guest? and not newcomer?

    by_format = if figures? and not guest?, do: [{format, Demo.stats()}], else: []

    schedule =
      if session && (stage != :signup or Keyword.get(opts, :registered, true)),
        do: [%{session: session, club: session.club, role: "speaker"}],
        else: []

    member? = Keyword.get(opts, :membership, "approved") == "approved"

    open_sessions =
      cond do
        stage != :signup or not member? -> []
        guest? -> [%{session: session, club: session.club, registered: true}]
        true -> [%{session: session, club: session.club, registered: schedule != []}]
      end

    registering =
      if Keyword.get(opts, :registering) do
        %{
          session: session,
          kind: :member,
          fields: Cab.Clubs.member_fields(session.club),
          values: Core.Forms.answer_values(Demo.membership(user).answers),
          errors: %{}
        }
      end

    seats =
      if state,
        do: seats(user, session, state, Keyword.get(opts, :feedback_sent, false)),
        else: []

    {CabWeb.MeHTML, :show,
     base(user, nil, :public, %{
       guest: guest?,
       by_format: by_format,
       stats: if(by_format != [], do: Demo.stats()),
       stats_format: if(by_format != [], do: format),
       stats_formats: Enum.map(by_format, &elem(&1, 0)),
       invitations: [],
       memberships:
         if(guest?,
           do: [],
           else: [%{Demo.membership(user) | status: Keyword.get(opts, :membership, "approved")}]
         ),
       tonight: %{-1 => session && {session, stage, length(state.rooms)}},
       schedule: schedule,
       history:
         if(guest? or newcomer?,
           do: [],
           else: Demo.history(if(user == Demo.chair(), do: "adjudicator", else: "speaker"))
         ),
       feedback_on_me: if(Keyword.get(opts, :on_me), do: on_me(), else: []),
       ballot_drafts: %{},
       feedback_drafts: %{},
       registering: registering,
       seats: seats,
       open_sessions: open_sessions,
       page_title: if(guest?, do: gettext("Personal link"), else: gettext("My page"))
     })}
  end

  # where `user` sits, as `Cab.Sessions.user_seats/1` and My page's
  # feedback read give it
  defp seats(user, session, state, sent?) do
    for room <- state.rooms,
        seat = seat_in(room, user),
        seat != nil do
      feedback =
        cond do
          seat.role != :speaker or room["status"] not in ["completed", "confirmed"] -> nil
          sent? -> {:sent, hd(Demo.feedback(:running))}
          true -> :open
        end

      Map.merge(
        %{session: session, club: session.club, state: state, room: room, feedback: feedback},
        seat
      )
    end
  end

  defp seat_in(room, user) do
    pid = participant_id(user)

    team =
      Enum.find(room["RoomTeams"], fn room_team ->
        Enum.any?(room_team["RoomSpeakers"], &(&1["EventParticipant"]["id"] == pid))
      end)

    chair? = Enum.any?(room["RoomAdjudicators"], &(&1["EventParticipant"]["id"] == pid))

    cond do
      chair? -> %{role: :chair, room_team: nil, participant_ids: [pid]}
      team -> %{role: :speaker, room_team: team, participant_ids: [pid]}
      true -> nil
    end
  end

  # the followed people's places; the guest sits on R1's chair for the tour
  defp participant_id(user) do
    cond do
      user == Demo.speaker() -> 201
      user == Demo.chair() -> 217
      Map.get(user, :guest) -> 217
      true -> nil
    end
  end

  defp on_me do
    session = Demo.session(:done)
    state = Demo.state(:done)

    [
      %{
        session: session,
        state: state,
        entries: Enum.map(Demo.feedback(:done), &Map.drop(&1, [:team, :team_id, :id])),
        average: 7.3
      }
    ]
  end

  # the head's session page at `stage`, showing `view`
  defp owner(stage, view) do
    club = Demo.club()
    session = Demo.session(stage)
    state = Demo.state(stage, :completed)
    feedback = if stage in [:running, :done], do: Demo.feedback(stage), else: []

    {CabWeb.OwnerHTML, :session,
     base(Demo.head(), club, :owner, %{
       current: session,
       state: state,
       view: view,
       club_sessions: [session | Demo.past_sessions()],
       short_url: short_url(),
       zone: "Europe/Kyiv",
       query: "",
       selected: MapSet.new(),
       confirm_remove: false,
       refused: [],
       draft: Cab.Sessions.draft(session, state.signups),
       links: [Demo.guest_link()],
       invitations: %{},
       members: Demo.members(),
       my_ballot_room: nil,
       feedback: feedback,
       feedback_progress: Cab.Feedback.progress(state, feedback),
       feedback_missing: Cab.Feedback.missing(state, feedback),
       suggestions: %{members: [], users: [], guest: nil},
       page_title: "#{club.name} — #{state.event["name"]}"
     })}
  end
end
