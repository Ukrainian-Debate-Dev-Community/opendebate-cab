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

  # the other open sessions, linked like the standings' session selector
  defp other_choices(%{choices: choices, session: session}),
    do: Enum.reject(choices, &(&1.session.id == session.id))

  defp session_title(session), do: session.name || gettext("The next session")

  @doc """
  The club page's registration section (#register) for the chosen
  session (with several taking sign-ups, the others are linked as in
  the standings' session selector): a form while it takes sign-ups (the guest form,
  or the member's / account's fields as themselves), the guest's
  personal link once registered, else where things stand.
  """
  attr :club, :map, required: true
  attr :registration, :map, required: true

  def registration_section(assigns) do
    ~H"""
    <div id="register">
      <.section title={gettext("Registration")}>
        <div class="pad scope-card">
          <p>
            <b>{session_title(@registration.session)}</b>
            <span :if={@registration.session.scheduled_at}>
              — <.local_time at={@registration.session.scheduled_at} as={:weekday_time} />
            </span>
          </p>
          <div :if={other_choices(@registration) != []} class="flinks">
            <span class="mut">{gettext("also open:")}</span>
            <.link
              :for={choice <- other_choices(@registration)}
              href={~p"/c/#{@club.uuid}?#{[session: choice.session.uuid]}" <> "#register"}
            >
              {session_title(choice.session)}<span :if={choice.session.scheduled_at}>,
              <.local_time
                at={choice.session.scheduled_at}
                as={:weekday_time}
              /></span><span :if={choice.registered}> ({gettext("you are registered")})</span>
            </.link>
          </div>
        </div>
        <%= case {@registration.kind, @registration.done} do %>
          <% {:guest, %{} = done} -> %>
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
              <:submit note={
                gettext(
                  "You appear in this session's list right away; the club head seats you as a speaker or the adjudicator."
                )
              }>
                {gettext("Register")}
              </:submit>
            </.form_for>
          <% {:registered, _done} -> %>
            <div class="pad">
              <p>{gettext("You are registered for this session.")}</p>
              <p>
                <.link href={~p"/c/#{@club.uuid}/s/#{@registration.session.uuid}"}>
                  {gettext("Open the session page")}
                </.link>
              </p>
              <.link
                :if={@registration.signup}
                href={
                  ~p"/c/#{@club.uuid}/s/#{@registration.session.uuid}/signups/#{@registration.signup["id"]}/remove?from=club"
                }
                method="post"
                class="btn-quiet btn-sm"
              >
                {gettext("Cancel my registration")}
              </.link>
            </div>
          <% {:closed, _done} -> %>
            <div class="pad">
              {gettext("Registration is closed for this session.")}
              {gettext("Ask the club head about the next session.")}
            </div>
          <% {:running, _done} -> %>
            <div class="pad">
              {gettext("The session is running.")}
              <.link href={~p"/c/#{@club.uuid}/s/#{@registration.session.uuid}"}>
                {gettext("watch rooms")}
              </.link>
            </div>
          <% _other -> %>
        <% end %>
      </.section>
    </div>
    """
  end
end
