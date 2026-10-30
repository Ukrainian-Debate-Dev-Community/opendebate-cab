defmodule PublicTest do
  use ExUnit.Case, async: true

  test "portal reads tournaments through cab's public context" do
    Req.Test.stub(Core.Engine, fn conn ->
      assert conn.request_path == "/api/events"

      Req.Test.json(conn, %{
        "status" => "success",
        "data" => [%{"id" => 1, "name" => "Northport Open", "status" => "scheduled"}]
      })
    end)

    assert {:ok, [%{"name" => "Northport Open"}]} = Public.tournaments()
  end
end
