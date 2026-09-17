# Shared helpers for the acceptance walkthrough scripts
# (walkthrough.exs, walkthrough_club.exs). Loaded via Code.require_file.

alias Cab.Accounts
alias Cab.Accounts.User
alias Cab.Repo

defmodule Walk do
  def check!(label, result) do
    case result do
      {:ok, value} ->
        IO.puts("  ok  #{label}")
        value

      :ok ->
        IO.puts("  ok  #{label}")
        :ok

      {:error, reason} ->
        IO.puts("  FAIL #{label}: #{inspect(reason)}")
        raise "walkthrough failed at: #{label}"

      other ->
        IO.puts("  ok  #{label} -> #{inspect(other)}")
        other
    end
  end

  def gateway_user!(username) do
    user =
      Repo.get_by(User, username: username) ||
        Repo.insert!(User.changeset(%User{}, %{username: username}))

    user = Accounts.ensure_node_user(user)

    if user.node_user_id == nil do
      raise "could not provision engine user for #{username} — is the engine up?"
    end

    user
  end
end
