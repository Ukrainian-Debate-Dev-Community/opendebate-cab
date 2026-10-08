defmodule Mix.Tasks.Cab.BackfillSessions do
  @shortdoc "Records lifecycle facts for sessions that predate them"
  @moduledoc """
  One-off: every session row gets its name, start, room count, finish
  and winner recorded from one engine read (see
  `Cab.Sessions.backfill/1`). Safe to re-run.

      mix cab.backfill_sessions
  """
  use Mix.Task

  @requirements ["app.start"]

  @impl true
  def run(_args) do
    sessions = Cab.Repo.all(Cab.Sessions.Session) |> Cab.Repo.preload(:club)

    for session <- sessions do
      case Cab.Sessions.backfill(session) do
        :ok -> Mix.shell().info("recorded #{session.uuid}")
        {:error, message} -> Mix.shell().error("skipped #{session.uuid}: #{inspect(message)}")
      end
    end
  end
end
