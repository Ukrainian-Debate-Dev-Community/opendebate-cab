defmodule PublicWeb.ConnCase do
  @moduledoc """
  Requests against the public site with both databases in the sandbox:
  cab's (accounts, clubs, read downward) and the site's own.
  """
  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      @endpoint PublicWeb.Endpoint

      use Phoenix.VerifiedRoutes,
        endpoint: PublicWeb.Endpoint,
        router: PublicWeb.Router,
        statics: PublicWeb.static_paths()

      import Plug.Conn
      import Phoenix.ConnTest
      import PublicWeb.ConnCase
    end
  end

  setup tags do
    for repo <- [Cab.Repo, Public.Repo] do
      pid = Sandbox.start_owner!(repo, shared: not tags[:async])
      on_exit(fn -> Sandbox.stop_owner(pid) end)
    end

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc "A cab account, inserted straight into cab's database."
  def cab_user(attrs \\ %{}) do
    unique = System.unique_integer([:positive])
    {admin?, attrs} = Map.pop(attrs, :is_admin, false)

    %Cab.Accounts.User{node_user_id: 5000 + unique, is_admin: admin?}
    |> Cab.Accounts.User.changeset(Map.merge(%{username: "person-#{unique}"}, attrs))
    |> Cab.Repo.insert!()
  end

  @doc "A cab club with a head, as cab's own fixtures make it."
  def cab_club(head, attrs \\ %{}) do
    club =
      %Cab.Clubs.Club{engine_organisation_id: 3}
      |> Cab.Clubs.Club.changeset(
        Map.merge(%{name: "Club #{System.unique_integer([:positive])}"}, attrs)
      )
      |> Cab.Repo.insert!()

    %Cab.Clubs.Membership{user_id: head.id, club_id: club.id}
    |> Cab.Clubs.Membership.changeset(%{role: "head", status: "approved"})
    |> Cab.Repo.insert!()

    club
  end

  @doc "Signs the request in to cab: cab's own session cookie, as cab sets it."
  def cab_sign_in(conn, user) do
    signed =
      Plug.Test.conn(:get, "/")
      |> Map.put(:secret_key_base, CabWeb.Endpoint.config(:secret_key_base))
      |> Plug.Session.call(Plug.Session.init(CabWeb.Session.options()))
      |> Plug.Conn.fetch_session()
      |> Plug.Conn.put_session(:user_id, user.id)
      |> Plug.Conn.send_resp(200, "")

    # the throwaway response above reports itself to the test process;
    # drop that so assert_error_sent sees only the real request
    receive do
      {ref, {200, _headers, ""}} when is_reference(ref) -> :ok
    after
      0 -> :ok
    end

    receive do
      {:plug_conn, :sent} -> :ok
    after
      0 -> :ok
    end

    key = CabWeb.Session.cookie_key()
    Plug.Test.put_req_cookie(conn, key, signed.resp_cookies[key].value)
  end
end
