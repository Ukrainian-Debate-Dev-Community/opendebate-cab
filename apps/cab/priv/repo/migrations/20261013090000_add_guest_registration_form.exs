defmodule Cab.Repo.Migrations.AddGuestRegistrationForm do
  use Ecto.Migration

  # the club's guest registration form: the head's own fields after
  # the built-in name, as a list of field maps with stable ids (empty
  # = nothing asked). A guest's answers sit on their personal link,
  # each with the field's label and type copied at answer time, so
  # later form edits never change old answers; they go wherever the
  # link goes (a removed or claimed guest takes them along).
  def change do
    alter table(:clubs) do
      add :guest_form, :jsonb, default: "[]", null: false
    end

    alter table(:links) do
      add :answers, :jsonb, default: "[]", null: false
    end
  end
end
