defmodule Public.EventRequests do
  @moduledoc """
  The public asks for an event in the calendar: a form content
  managers edit (a Core.Forms definition kept in site_forms, the
  requester's e-mail always first), the requests it brings, and the
  content manager's decision. Accepting happens when the event is saved
  from the request's prefilled New event form; declining may carry a
  reason. Requests are kept until deleted with their data (no automatic
  purge).
  """
  use Gettext, backend: PublicWeb.Gettext

  import Ecto.Query

  alias Public.EventRequests.{Request, SiteForm}
  alias Public.Repo

  @key "event_request"

  @doc "The fixed first field: the e-mail the request's copy goes to."
  def locked do
    [
      %{
        "id" => "email",
        "type" => "email",
        "label" => "Your e-mail",
        "hint" => nil,
        "required" => true,
        "options" => []
      }
    ]
  end

  # the editable fields a fresh site starts with (stable ids: Accept
  # maps them onto the event), worded in the editor's language
  defp defaults do
    [
      field("name", "text", gettext("Event name"), true),
      field("dates", "text", gettext("Dates"), true, gettext("For example 14-16 November 2026")),
      field("city", "text", gettext("City"), false),
      field("format", "text", gettext("Format"), false, gettext("For example BP, APF, WSDC")),
      field("details", "longtext", gettext("Details"), false)
    ]
  end

  defp field(id, type, label, required, hint \\ nil) do
    %{
      "id" => id,
      "type" => type,
      "label" => label,
      "hint" => hint,
      "required" => required,
      "options" => [],
      "locked" => false
    }
  end

  @doc "The request form, its e-mail first (Core.Forms.with_locked/2)."
  def form do
    stored =
      case Repo.get_by(SiteForm, key: @key) do
        %SiteForm{definition: [_ | _] = definition} -> definition
        _ -> defaults()
      end

    Core.Forms.with_locked(stored, locked())
  end

  @doc """
  The content manager edits the form: `edit` gets the current
  definition and returns `{:ok, definition}` (saved) or an error.
  """
  def edit_form(edit, user_id) when is_function(edit, 1) do
    with {:ok, definition} <- edit.(form()) do
      now = DateTime.utc_now(:second)

      Repo.insert(
        %SiteForm{
          key: @key,
          definition: definition,
          updated_by_user_id: user_id,
          inserted_at: now,
          updated_at: now
        },
        on_conflict: [set: [definition: definition, updated_by_user_id: user_id, updated_at: now]],
        conflict_target: :key
      )
    end
  end

  @doc """
  A request from the public: the answers by field id. `{:ok, request}`
  or `{:error, codes}` (Core.Forms answer codes by field id).
  """
  def submit(params, locale) do
    case Core.Forms.validate_answers(form(), params, Cab.Clubs.answer_opts()) do
      {:ok, answers} ->
        %Request{
          email: Core.Forms.first_value(answers, "email"),
          answers: answers,
          locale: locale
        }
        |> Repo.insert()

      {:error, codes} ->
        {:error, codes}
    end
  end

  def get!(id), do: Repo.get!(Request, id)

  @doc "Pending requests, oldest first."
  def pending do
    Repo.all(from r in Request, where: r.status == "pending", order_by: [asc: r.inserted_at])
  end

  @doc "Decided requests, latest decision first."
  def decided(limit \\ 50) do
    Repo.all(
      from r in Request,
        where: r.status != "pending",
        order_by: [desc: r.decided_at, desc: r.id],
        limit: ^limit
    )
  end

  @doc "Accepted: the event saved from the request's prefilled form."
  def accept(%Request{status: "pending"} = request, event_id, user_id) do
    decide(request, %{status: "accepted", event_id: event_id}, user_id)
  end

  def accept(_request, _event_id, _user_id), do: {:error, :decided}

  @doc "Declined, with the content manager's optional reason."
  def decline(%Request{status: "pending"} = request, reason, user_id) do
    reason =
      case Core.Text.clean(reason, max: 1000, multiline: true) do
        {:ok, text} -> text
        _ -> nil
      end

    decide(request, %{status: "declined", reason: reason}, user_id)
  end

  def decline(_request, _reason, _user_id), do: {:error, :decided}

  defp decide(request, changes, user_id) do
    request
    |> Ecto.Changeset.change(
      Map.merge(changes, %{decided_by_user_id: user_id, decided_at: DateTime.utc_now(:second)})
    )
    |> Repo.update()
  end

  @doc """
  New event attributes from a request's answers (the default fields'
  ids): the name as the title, dates when they read as one or two
  dates, the city and format; anything else - and dates that do not
  read - into the details.
  """
  def event_attrs(%Request{answers: answers}) do
    value = fn id -> Enum.find_value(answers, &(&1["id"] == id && text(&1["value"]))) end
    {starts, ends} = dates(value.("dates"))

    extra =
      for answer <- answers,
          answer["id"] not in ~w(email name city format details) or
            (answer["id"] == "dates" and is_nil(starts)),
          text = text(answer["value"]),
          text not in [nil, ""],
          do: "#{answer["label"]}: #{text}"

    details = Enum.join(Enum.reject([value.("details") | extra], &is_nil/1), "\n\n")

    %{
      "title" => value.("name"),
      "starts_on" => starts && Date.to_iso8601(starts),
      "ends_on" => ends && Date.to_iso8601(ends),
      "city" => value.("city"),
      "format" => value.("format"),
      "details" => if(details == "", do: nil, else: details)
    }
  end

  defp text(true), do: gettext("yes")
  defp text(false), do: gettext("no")
  defp text(values) when is_list(values), do: Enum.join(values, ", ")
  defp text(value) when is_binary(value), do: value
  defp text(_value), do: nil

  # "2026-11-14", "2026-11-14 - 2026-11-16", "14.11.2026-16.11.2026"
  defp dates(nil), do: {nil, nil}

  defp dates(text) do
    found =
      Regex.scan(~r/\d{4}-\d{2}-\d{2}|\d{1,2}\.\d{1,2}\.\d{4}/, text)
      |> List.flatten()
      |> Enum.map(&parse_date/1)
      |> Enum.reject(&is_nil/1)

    case found do
      [one] -> {one, nil}
      [from, to | _] -> {from, to}
      [] -> {nil, nil}
    end
  end

  defp parse_date(text) do
    case String.split(text, ".") do
      [d, m, y] ->
        with {:ok, date} <- Date.new(int(y), int(m), int(d)), do: date, else: (_ -> nil)

      _ ->
        with {:ok, date} <- Date.from_iso8601(text), do: date, else: (_ -> nil)
    end
  end

  defp int(text), do: String.to_integer(text)
end
