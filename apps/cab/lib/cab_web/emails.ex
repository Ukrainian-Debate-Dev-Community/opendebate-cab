defmodule CabWeb.Emails do
  @moduledoc """
  cab's e-mails, plain text, delivered through Core.Mailer. An address
  typed by a club head is used once to send and never stored.
  """
  use CabWeb, :verified_routes
  use Gettext, backend: CabWeb.Gettext

  import Swoosh.Email

  alias Cab.Accounts.User
  alias Cab.Clubs.{Club, HeadInvitation}
  alias Cab.Links.Link
  alias Cab.Sessions.Session

  @doc "A guest's personal link, sent to the address the club head typed."
  def guest_link(address, %Link{} = link, %Session{} = session, %Club{} = club) do
    deliver(
      address,
      gettext("Your link to %{session}", session: session_name(session, club)),
      gettext(
        """
        Hello %{name},

        %{club} added you to %{session}. This personal link is your way in: it shows the session, your seat and your room.

        %{url}

        Anyone with this link acts as you, so keep it to yourself. If you sign in to cab later, you can move your results into your account from this link.
        """,
        name: link.user.name,
        club: club.name,
        session: session_name(session, club),
        url: url(~p"/l/#{link.code}")
      )
    )
  end

  @doc "Tells a registered user that a club head added them to a session."
  def invitation(%User{email: address} = user, %Session{} = session, %Club{} = club)
      when is_binary(address) and address != "" do
    deliver(
      address,
      gettext("%{club} added you to %{session}",
        club: club.name,
        session: session_name(session, club)
      ),
      gettext(
        """
        Hello %{name},

        The head of %{club} added you to %{session}. Accept or decline on your page in cab:

        %{url}
        """,
        name: user.name || user.username,
        club: club.name,
        session: session_name(session, club),
        url: url(~p"/me")
      )
    )
  end

  def invitation(_user, _session, _club), do: {:error, :no_address}

  @doc "An invitation to head a club, sent to the address an admin typed."
  def head_invitation(%HeadInvitation{} = invitation, token, %User{} = inviter) do
    deliver(
      invitation.email,
      gettext("%{club}: you are invited to be its head", club: invitation.club.name),
      gettext(
        """
        Hello %{name},

        %{inviter} invites you to be the head of %{club} in cab, where debate clubs run their sessions.

        Open this link and sign in with GitHub or Google; you become the head as soon as you are signed in:

        %{url}

        The link works once and expires on %{date}.
        """,
        name: invitation.name,
        inviter: inviter.name || inviter.username,
        club: invitation.club.name,
        url: head_invitation_url(token),
        date: Calendar.strftime(invitation.expires_at, "%Y-%m-%d")
      )
    )
  end

  @doc "The link inside a head invitation."
  def head_invitation_url(token), do: url(~p"/head-invitations/#{token}")

  defp deliver(address, subject, body) do
    new()
    |> to(address)
    |> from(Application.fetch_env!(:cab, :mail_from))
    |> subject(subject)
    |> text_body(body)
    |> Core.Mailer.deliver()
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp session_name(%Session{name: name}, _club) when is_binary(name) and name != "", do: name
  defp session_name(_session, _club), do: gettext("a session")
end
