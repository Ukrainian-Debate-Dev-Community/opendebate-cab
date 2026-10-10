defmodule CabWeb.FeedbackHTML do
  @moduledoc "The team's feedback form on its room's adjudicator, or what it sent."
  use CabWeb, :html

  embed_templates "feedback_html/*"

  defp score_words(nil), do: "—"
  defp score_words(score), do: points_words(score)
end
