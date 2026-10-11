defmodule Cab.Repo.Migrations.AddClubProfileAndJoinAnswers do
  use Ecto.Migration

  def change do
    alter table(:clubs) do
      # the club profile card (P4): shown publicly, edited in place by
      # the owner / admin
      add :meeting_info, :text
      add :description, :text
      add :contacts, :text
      # admin archive flag - archived clubs disappear from every
      # public surface; the engine organisation stays untouched
      add :archived_at, :utc_datetime
    end

    alter table(:memberships) do
      # the join-request form's answers (user params by design): the
      # head reads them in Requests before approving
      add :message, :text
      add :contact, :string
    end
  end
end
