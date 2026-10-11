defmodule Cab.AccountsLoginTest do
  use Cab.DataCase, async: true

  import Cab.Fixtures

  alias Cab.Accounts

  test "finds an account by exact username or e-mail, any case" do
    user = user_fixture(%{username: "olena", email: "Olena@Example.org"})
    assert Accounts.get_user_by_login("OLENA").id == user.id
    assert Accounts.get_user_by_login(" olena@example.org ").id == user.id
    assert Accounts.get_user_by_login("olen") == nil
    assert Accounts.get_user_by_login("") == nil
    assert Accounts.get_user_by_login(nil) == nil
  end
end
