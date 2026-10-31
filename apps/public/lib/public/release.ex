defmodule Public.Release do
  @moduledoc """
  Tasks a release runs without Mix, e.g.
  `bin/full eval "Public.Release.migrate()"`.
  """
  @app :public

  def migrate do
    Application.load(@app)

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end
end
