defmodule Mix.Tasks.Cab.SeedClub do
  @shortdoc "Creates a club with an existing user as head (admin seed)"

  @moduledoc """
  Club creation is deliberately NOT in the API — an admin seeds clubs:

      mix cab.seed_club "Kyiv Debate" "Kyiv" head_username

  Creates the engine organisation (owned by the head's node user) and
  the gateway club + head membership rows. The head user must already
  exist (e.g. via /dev/switch-user) and the engine must be running.
  Usable repeatedly in dev — every run seeds a fresh club.

  The last line of output is `CLUB_UUID=<uuid>` for scripting.
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run([name, city, head_username]) do
    case Cab.Repo.get_by(Cab.Accounts.User, username: head_username) do
      nil ->
        Mix.raise("no user #{inspect(head_username)} — sign them in once first")

      head ->
        case Cab.Clubs.create_club(name, city, head) do
          {:ok, club} ->
            Mix.shell().info("club #{inspect(club.name)} seeded, head: #{head.username}")
            Mix.shell().info("CLUB_UUID=#{club.uuid}")

          {:error, %Ecto.Changeset{} = changeset} ->
            Mix.raise("club row invalid: #{inspect(changeset.errors)}")

          {:error, message} ->
            Mix.raise("could not seed club: #{message}")
        end
    end
  end

  def run(_argv) do
    Mix.raise(~s(usage: mix cab.seed_club "Name" "City" <head_username>))
  end
end
