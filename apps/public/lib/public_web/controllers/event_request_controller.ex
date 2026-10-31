defmodule PublicWeb.EventRequestController do
  @moduledoc """
  The public's request for an event in the calendar: the form content
  managers set up (Public.EventRequests), Turnstile when its keys are
  set, and at most 5 requests per address per hour. A sent request
  e-mails the requester a copy and notifies the address that receives
  requests.
  """
  use PublicWeb, :controller

  alias Public.EventRequests
  alias PublicWeb.Emails

  # 5 requests per address per hour (cab's token buckets)
  @per_hour 5

  def new(conn, _params), do: render_form(conn, %{}, %{})

  def create(conn, params) do
    answers = if is_map(params["answers"]), do: params["answers"], else: %{}
    ip = CabWeb.RateLimit.client_ip(conn)

    with :ok <- turnstile(params, ip),
         {:ok, _answers} <-
           Core.Forms.validate_answers(EventRequests.form(), answers, Cab.Clubs.answer_opts()),
         :ok <- take(ip),
         {:ok, request} <- EventRequests.submit(answers, conn.assigns.locale) do
      Emails.request_received(request)
      Emails.request_notice(request)
      render(conn, :sent, page_title: gettext("Request an event"), email: request.email)
    else
      {:error, :turnstile} ->
        conn
        |> put_status(422)
        |> render_form(answers, %{turnstile: gettext("Confirm you are not a robot.")})

      {:limited, seconds} ->
        conn
        |> put_status(429)
        |> put_resp_header("retry-after", Integer.to_string(seconds))
        |> render_form(answers, %{
          form:
            gettext(
              "Too many requests from this address. Please try again in %{minutes} minutes.",
              minutes: max(1, div(seconds + 59, 60))
            )
        })

      {:error, codes} when is_map(codes) ->
        errors = CabWeb.FormComponents.answer_errors(EventRequests.form(), codes)
        conn |> put_status(422) |> render_form(answers, errors)
    end
  end

  defp turnstile(params, ip) do
    case CabWeb.Turnstile.verify(params["cf-turnstile-response"], ip) do
      :ok -> :ok
      {:error, _reason} -> {:error, :turnstile}
    end
  end

  # only a request that would be saved takes from the address's bucket
  defp take(ip) do
    case CabWeb.RateLimit.take({:event_request, ip}, @per_hour / 60, @per_hour) do
      {:ok, _left, _full_in} -> :ok
      {:error, retry} -> {:limited, retry}
    end
  end

  defp render_form(conn, answers, errors) do
    render(conn, :new,
      active: :calendar,
      page_title: gettext("Request an event"),
      fields: EventRequests.form(),
      answers: answers,
      errors: errors
    )
  end
end
