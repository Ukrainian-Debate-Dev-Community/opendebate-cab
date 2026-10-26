defmodule CabWeb.ClubPublicHTML do
  @moduledoc """
  The club's public pages: the club page (profile + Club Sessions), the
  club standings (teams, speakers, judges) and the join-request form.
  """
  use CabWeb, :html

  import CabWeb.StandingsHTML, only: [standings_tabs: 1, standings_body: 1]

  import CabWeb.FormComponents,
    only: [
      answer_name: 1,
      block_type: 1,
      field_label: 1,
      input_type: 1,
      placeholder: 1,
      prompt: 1
    ]

  embed_templates "club_public_html/*"

  # list_members/1 orders head first
  defp head_name([%{user: user} | _rest]), do: user.name || user.username
  defp head_name([]), do: nil

  # the section's own form is the page's gold action while it is open
  defp form_open?(%{kind: kind, done: nil}) when kind in [:guest, :member, :account], do: true
  defp form_open?(_registration), do: false

  # the session line shows above a form (and a running session)
  defp header?(%{done: %{}}), do: false
  defp header?(%{kind: kind}), do: kind in [:guest, :member, :account, :full, :running]

  # the places left under the session's limit, while it takes sign-ups
  defp places_left(%{kind: kind, session: session}) when kind in [:guest, :member, :account],
    do: Cab.Sessions.places_left(session)

  defp places_left(_registration), do: nil

  # the Register button's menu: the other sessions taking sign-ups the
  # viewer is not registered for,
  # each opening this section for itself
  defp session_menu(club, %{choices: choices, session: session}) do
    for %{session: other, registered: false} <- choices, other.id != session.id do
      %{
        label: session_title(other),
        href: ~p"/c/#{club.uuid}?#{[session: other.uuid]}" <> "#register",
        at: other.scheduled_at
      }
    end
  end

  defp session_title(session), do: session.name || gettext("The next session")

  @doc """
  The club page's registration section (#register) for the chosen
  session (with several taking sign-ups, Register's menu switches to
  another): a form while it takes sign-ups (the guest form,
  or the member's / account's fields as themselves), the guest's
  personal link once registered, else where things stand. With a
  participant limit the places left show above the form, and a full
  session says so instead of the form.
  """
  attr :club, :map, required: true
  attr :registration, :map, required: true

  def registration_section(assigns) do
    ~H"""
    <div id="register">
      <.section title={gettext("Registration")}>
        <div :if={@registration.notice && !@registration.done} class="pad">
          <.banner kind={:good}>
            {gettext("You are registered for")}
            <b>{session_title(@registration.notice)}</b><span :if={@registration.notice.scheduled_at}>, <.local_time at={@registration.notice.scheduled_at} as={:short} /></span>.
          </.banner>
        </div>
        <div :if={header?(@registration)} class="pad scope-card">
          <p>
            <b>{session_title(@registration.session)}</b><span :if={
              @registration.session.scheduled_at
            }>,
            <.local_time
              at={@registration.session.scheduled_at}
              as={:short}
            /></span>
          </p>
          <p :if={places_left(@registration)}>
            {ngettext("%{count} place left", "%{count} places left", places_left(@registration))}
          </p>
        </div>
        <%= case {@registration.kind, @registration.done} do %>
          <% {_kind, %{} = done} -> %>
            <div class="pad">
              <.banner kind={:good}>
                {gettext("You are registered as %{name}.", name: done.link.user.name)}
              </.banner>
              <.copy_banner id="personal-link" url={done.personal_url}>
                {gettext("Personal link")}
              </.copy_banner>
              <p :if={match?({:sent, _}, done.mail)}>
                {gettext("We also sent it to %{email}.", email: elem(done.mail, 1))}
              </p>
              <p :if={match?({:failed, _}, done.mail)}>
                {gettext("We could not send it to %{email}. Copy it now.",
                  email: elem(done.mail, 1)
                )}
              </p>
              <p>
                {gettext(
                  "Keep this link — it IS your access: anyone with it acts as you. It opens your view of this session: your registration, the rooms, and (if you adjudicate) the ballot."
                )}
              </p>
              <p><.link href={~p"/l/#{done.link.code}"}>{gettext("Open my session page")}</.link></p>
            </div>
          <% {:guest, nil} -> %>
            <CabWeb.RegistrationHTML.guest_form
              action={~p"/c/#{@club.uuid}/register"}
              hidden={[{"session", @registration.session.uuid}]}
              title={
                gettext("Register for %{session}", session: session_title(@registration.session))
              }
              fields={@registration.fields}
              logo={CabWeb.ClubProfile.logo_path(@club)}
              menu={session_menu(@club, @registration)}
              name={@registration.name}
              answers={@registration.values}
              errors={@registration.errors}
            />
            <div class="pad">
              {gettext("Have an account?")}
              <.link href={
                ~p"/signin?#{[return_to: "/c/#{@club.uuid}?session=#{@registration.session.uuid}#register"]}"
              }>
                {gettext("Sign in")}
              </.link>
              {gettext("to register as yourself.")}
            </div>
          <% {kind, _done} when kind in [:member, :account] -> %>
            <.form_for
              id="register-form"
              action={~p"/c/#{@club.uuid}/register"}
              hidden={[{"session", @registration.session.uuid}]}
              title={
                gettext("Register for %{session}", session: session_title(@registration.session))
              }
              logo={CabWeb.ClubProfile.logo_path(@club)}
              description={
                if kind == :member,
                  do:
                    gettext(
                      "Your saved answers are filled in. Changes here are for this session only; your defaults change on My page."
                    ),
                  else: gettext("You register with your account; one registration per session.")
              }
              errors={@registration.errors}
            >
              <:block
                :for={field <- @registration.fields}
                name={answer_name(field)}
                type={block_type(field)}
                label={field_label(field)}
                required={field["required"]}
                hint={field["hint"]}
                options={field["options"]}
                value={@registration.values[field["id"]]}
                input={input_type(field)}
                placeholder={placeholder(field)}
                prompt={prompt(field)}
              />
              <:submit
                menu={session_menu(@club, @registration)}
                note={
                  gettext(
                    "You appear in this session's list right away; the club head seats you as a speaker or the adjudicator."
                  )
                }
              >
                {gettext("Register")}
              </:submit>
            </.form_for>
          <% {:full, _done} -> %>
            <div class="pad">
              {gettext("Registration is full.")}
              {gettext("Ask the club head about the next session.")}
            </div>
          <% {:registered, _done} -> %>
            <div class="pad">
              <p>
                {gettext("You are registered for this session.")}
                {gettext("Cancel or open it in Club Sessions below.")}
              </p>
            </div>
          <% {:all_registered, _done} -> %>
            <div class="pad">
              <p>{gettext("You are registered for every session open for registration:")}</p>
              <p :for={choice <- @registration.choices}>
                <b>{session_title(choice.session)}</b><span :if={choice.session.scheduled_at}>,
                <.local_time
                  at={choice.session.scheduled_at}
                  as={:short}
                /></span>
              </p>
              <p>{gettext("Cancel or open them in Club Sessions below.")}</p>
            </div>
          <% {:closed, _done} -> %>
            <div class="pad">
              {gettext("No sessions are open for registration right now.")}
              {gettext("Ask the club head about the next session.")}
            </div>
          <% {:running, _done} -> %>
            <div class="pad">
              {gettext("The session is running.")}
              <.link href={~p"/c/#{@club.uuid}/s/#{@registration.session.uuid}"}>
                {gettext("watch rooms")}
              </.link>
              <p>{gettext("No sessions are open for registration right now.")}</p>
            </div>
          <% _other -> %>
        <% end %>
      </.section>
    </div>
    """
  end
end
