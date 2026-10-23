defmodule CabWeb.MeController do
  @moduledoc """
  GET /me - the signed-in user's personal page: invitations to
  accept, my clubs and schedule, engine statistics VERBATIM
  (`GET /users/:id/stats`, rule 0 - cab never derives its own
  numbers) plus the participation history rows.
  """
  use CabWeb, :controller

  alias Cab.{Accounts, Clubs, EngineApi, Invitations, Sessions}

  import CabWeb.UserAuth, only: [require_account: 2]

  plug :require_account

  def show(conn, _params) do
    user = conn.assigns.current_user
    memberships = Clubs.list_user_memberships(user)

    clubs =
      for membership <- memberships, membership.status == "approved", do: membership.club

    render(conn, :show,
      invitations: Invitations.for_user(user),
      memberships: memberships,
      tonight: Sessions.next_by_club(clubs),
      schedule: Sessions.user_schedule(user),
      stats: fetch_stats(user),
      history: Sessions.user_history(user),
      feedback_to_give: Cab.Feedback.to_give(user),
      feedback_on_me: Cab.Feedback.on_me_recent(user),
      page_title: gettext("My page")
    )
  end

  # GET /me/clubs/:club_uuid/answers - the member's saved answers to
  # the club form's member fields, prefilled for editing
  def edit_answers(conn, %{"club_uuid" => club_uuid}) do
    with_membership(conn, club_uuid, fn conn, membership ->
      render_answers(conn, membership, Core.Forms.answer_values(membership.answers), %{})
    end)
  end

  # POST /me/clubs/:club_uuid/answers - saves them; registrations
  # start from them, a registration's own changes never come back here
  def update_answers(conn, %{"club_uuid" => club_uuid} = params) do
    with_membership(conn, club_uuid, fn conn, membership ->
      answers = answer_params(params)

      case Clubs.update_member_answers(membership, answers) do
        {:ok, _membership} ->
          conn
          |> put_flash(:info, gettext("Your answers are saved."))
          |> redirect(to: ~p"/me")

        {:error, {:answers, codes}} ->
          errors =
            CabWeb.FormComponents.answer_errors(Clubs.member_fields(membership.club), codes)

          conn |> put_status(422) |> render_answers(membership, answers, errors)
      end
    end)
  end

  defp answer_params(%{"answers" => %{} = answers}), do: answers
  defp answer_params(_params), do: %{}

  defp render_answers(conn, membership, answers, errors) do
    render(conn, :answers,
      club: membership.club,
      fields: Clubs.member_fields(membership.club),
      answers: answers,
      errors: errors,
      page_title: gettext("%{club} — My answers", club: membership.club.name)
    )
  end

  # only the signed-in user's own row in that club (pending included)
  defp with_membership(conn, club_uuid, fun) do
    with %Cab.Clubs.Club{} = club <- Clubs.get_by_uuid(club_uuid),
         %Cab.Clubs.Membership{} = membership <-
           Clubs.membership_of(club, conn.assigns.current_user) do
      fun.(conn, membership)
    else
      nil -> CabWeb.ErrorHTML.respond(conn, 404)
    end
  end

  # the engine's stats payload or nil (never participated / engine
  # trouble) - the page says so in words either way
  defp fetch_stats(user) do
    with %{node_user_id: id} when is_integer(id) <- Accounts.ensure_node_user(user),
         {:ok, stats} when is_map(stats) <- EngineApi.user_stats(id, id) do
      stats
    else
      _ -> nil
    end
  end
end
