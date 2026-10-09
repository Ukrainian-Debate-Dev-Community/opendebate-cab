defmodule CabWeb.AccountMergeTest do
  use CabWeb.ConnCase, async: true

  import Cab.Fixtures

  alias Cab.Accounts

  defp signed_in(conn, user, extra \\ %{}) do
    conn
    |> init_test_session(Map.merge(%{user_id: user.id}, extra))
    |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
  end

  test "the Account page offers to link whichever method is missing", %{conn: conn} do
    user = user_fixture()

    %Accounts.Identity{user_id: user.id}
    |> Accounts.Identity.changeset(%{provider: "github", provider_uid: "1"})
    |> Cab.Repo.insert!()

    html = conn |> signed_in(user) |> get(~p"/account") |> html_response(200)
    assert html =~ ~s(href="/account/link/google")
    assert html =~ "your only sign-in"

    linking = conn |> signed_in(user) |> get(~p"/account/link/google")
    assert redirected_to(linking) == "/auth/google"
    assert get_session(linking, :link_to) == user.id
  end

  test "a merge is offered only for the account just proven, and can be declined",
       %{conn: conn} do
    user = user_fixture()
    other = user_fixture(%{username: "second-me"})

    # without a candidate from a link, there is nothing to merge
    assert conn |> signed_in(user) |> get(~p"/account/merge") |> redirected_to() == "/account"

    page = conn |> signed_in(user, %{merge_candidate: other.id}) |> get(~p"/account/merge")
    assert html_response(page, 200) =~ "second-me"

    kept =
      conn
      |> signed_in(user, %{merge_candidate: other.id})
      |> post(~p"/account/merge", %{decision: "keep"})

    assert redirected_to(kept) == "/account"
    assert Cab.Repo.get(Accounts.User, other.id)
  end
end
