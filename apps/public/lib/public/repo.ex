defmodule Public.Repo do
  use Ecto.Repo, otp_app: :public, adapter: Ecto.Adapters.Postgres
end
