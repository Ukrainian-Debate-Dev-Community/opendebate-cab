defmodule Cab.Fixtures do
  @moduledoc """
  Row fixtures for club lifecycle tests. Everything is inserted
  directly (no engine calls); engine interactions are stubbed per
  test via `Req.Test`.
  """

  alias Cab.Accounts.User
  alias Cab.Clubs.{Club, Membership}
  alias Cab.Repo
  alias Cab.Sessions.Session

  def user_fixture(attrs \\ %{}) do
    unique = System.unique_integer([:positive])
    {node_user_id, attrs} = Map.pop(attrs, :node_user_id, 1000 + unique)

    %User{node_user_id: node_user_id}
    |> User.changeset(Map.merge(%{username: "user-#{unique}"}, attrs))
    |> Repo.insert!()
  end

  @doc "Club + head membership, engine org id preset (no engine call)."
  def club_fixture(%User{} = head, attrs \\ %{}) do
    club =
      %Club{engine_organisation_id: Map.get(attrs, :engine_organisation_id, 3)}
      |> Club.changeset(Map.merge(%{name: "Club #{System.unique_integer([:positive])}"}, attrs))
      |> Repo.insert!()

    membership_fixture(head, club, role: "head", status: "approved")
    club
  end

  def membership_fixture(%User{} = user, %Club{} = club, opts \\ []) do
    %Membership{user_id: user.id, club_id: club.id}
    |> Membership.changeset(%{
      role: Keyword.get(opts, :role, "member"),
      status: Keyword.get(opts, :status, "approved")
    })
    |> Repo.insert!()
  end

  def session_fixture(%Club{} = club, opts \\ []) do
    %Session{
      club_id: club.id,
      opened_by_user_id: Keyword.get(opts, :opened_by_user_id),
      engine_event_id: Keyword.get(opts, :engine_event_id, 11)
    }
    |> Session.changeset()
    |> Repo.insert!()
  end
end
