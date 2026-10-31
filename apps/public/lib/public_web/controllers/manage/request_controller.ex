defmodule PublicWeb.Manage.RequestController do
  @moduledoc """
  /manage/requests: the public's event requests - the pending ones with
  their answers (Accept opens New event prefilled from the request; the
  request counts accepted once that event is saved), Decline with an
  optional reason, the decided ones - and the request form's editor
  (cab's form editor over Public.EventRequests' definition).
  """
  use PublicWeb, :controller

  alias Core.Forms
  alias Public.EventRequests
  alias PublicWeb.Emails

  plug :put_view, PublicWeb.Manage.HTML

  # GET /manage/requests[?edit=<field id>]
  def index(conn, params) do
    editing = params["edit"] && Forms.field(EventRequests.form(), params["edit"])
    render_page(conn, editing, %{}, %{})
  end

  # POST /manage/requests/:id/decline {"reason"}
  def decline(conn, %{"id" => id} = params) do
    request = EventRequests.get!(id)

    case EventRequests.decline(request, params["reason"], conn.assigns.manager.id) do
      {:ok, request} ->
        Emails.request_declined(request)

        conn
        |> put_flash(:info, gettext("Request declined. The requester got an e-mail."))
        |> redirect(to: ~p"/manage/requests")

      {:error, :decided} ->
        conn
        |> put_flash(:error, gettext("This request was already decided."))
        |> redirect(to: ~p"/manage/requests")
    end
  end

  # the request form's editor: cab's field routes, the site's storage
  def add_field(conn, params) do
    conn
    |> edit_form(&Forms.add_field(&1, params), gettext("Field added."))
    |> on_field_error(nil, params)
  end

  def update_field(conn, %{"field_id" => id} = params) do
    conn
    |> edit_form(&Forms.update_field(&1, id, params), gettext("Field saved."))
    |> on_field_error(Forms.field(EventRequests.form(), id), params)
  end

  def remove_field(conn, %{"field_id" => id}) do
    conn
    |> edit_form(&Forms.remove_field(&1, id), gettext("Field removed."))
    |> on_field_error(nil, %{})
  end

  def move_field(conn, %{"field_id" => id, "direction" => direction})
      when direction in ["up", "down"] do
    conn
    |> edit_form(&Forms.move_field(&1, id, String.to_existing_atom(direction)), nil)
    |> on_field_error(nil, %{})
  end

  def move_field(_conn, _params), do: raise(PublicWeb.NotFound)

  defp edit_form(conn, edit, info) do
    case EventRequests.edit_form(edit, conn.assigns.manager.id) do
      {:ok, _form} ->
        conn = if info, do: put_flash(conn, :info, info), else: conn
        redirect(conn, to: ~p"/manage/requests#request-form")

      error ->
        {conn, error}
    end
  end

  defp on_field_error(%Plug.Conn{} = conn, _editing, _params), do: conn

  defp on_field_error({_conn, {:error, :not_found}}, _editing, _params),
    do: raise(PublicWeb.NotFound)

  defp on_field_error({conn, {:error, :locked}}, _editing, _params) do
    conn
    |> put_flash(:error, CabWeb.FormComponents.editor_error(:locked))
    |> redirect(to: ~p"/manage/requests#request-form")
  end

  defp on_field_error({conn, {:error, %{} = errors}}, editing, params),
    do: conn |> put_status(422) |> render_page(editing, params, errors)

  defp render_page(conn, editing, values, errors) do
    render(conn, :requests,
      manage_active: :requests,
      page_title: gettext("Requests"),
      pending: EventRequests.pending(),
      decided: EventRequests.decided(),
      definition: EventRequests.form(),
      editing: editing,
      values: Map.take(values, ~w(label hint type required options)),
      errors: errors
    )
  end
end
