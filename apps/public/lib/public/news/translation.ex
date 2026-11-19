defmodule Public.News.Translation do
  @moduledoc "A news post in another of the site's languages: its texts, cleaned as the post's are."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :lang, :string
    field :title, :string
    field :summary, :string
    field :body, :string, default: ""
    field :image_alt, :string
  end

  def changeset(translation, attrs) do
    translation
    |> cast(attrs, [:lang, :title, :summary, :body, :image_alt])
    |> Public.News.Post.clean_texts()
    |> validate_inclusion(:lang, Public.News.Post.langs())
  end
end
