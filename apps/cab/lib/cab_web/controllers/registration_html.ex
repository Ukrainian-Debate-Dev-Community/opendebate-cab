defmodule CabWeb.RegistrationHTML do
  @moduledoc """
  The guest registration form: the club page's registration section
  for visitors without an account, and the head's preview of it.
  """
  use CabWeb, :html

  import CabWeb.FormComponents,
    only: [
      answer_name: 1,
      block_type: 1,
      field_label: 1,
      input_type: 1,
      placeholder: 1,
      prompt: 1
    ]

  @doc """
  The guest's registration form: the built-in name, then the club's
  form fields (Cab.Clubs.guest_form/1). Also the head's preview of it,
  `preview` keeping its button from sending anything.
  """
  attr :action, :string, required: true
  attr :title, :string, required: true
  attr :fields, :list, required: true
  attr :name, :string, default: nil
  attr :answers, :map, default: %{}
  attr :errors, :map, default: %{}
  attr :preview, :boolean, default: false
  attr :logo, :string, default: nil, doc: "the club's logo beside the title"
  attr :hidden, :list, default: [], doc: "extra hidden inputs as {name, value}"
  attr :menu, :list, default: [], doc: "other choices beside Register (dropdown_button/1 items)"

  def guest_form(assigns) do
    ~H"""
    <.form_for
      id="guest-register-form"
      action={@action}
      hidden={@hidden}
      title={@title}
      logo={@logo}
      description={
        gettext("No account needed — you'll get a personal link that is your access to this session.")
      }
      errors={@errors}
      guard={!@preview}
    >
      <:block
        name={:name}
        type={:text}
        label={gettext("Your name")}
        required
        value={@name}
        maxlength={Cab.Links.name_max()}
      />
      <:block
        :for={field <- @fields}
        name={answer_name(field)}
        type={block_type(field)}
        label={field_label(field)}
        required={field["required"]}
        hint={field["hint"]}
        options={field["options"]}
        value={@answers[field["id"]]}
        input={input_type(field)}
        placeholder={placeholder(field)}
        prompt={prompt(field)}
        maxlength={Core.Forms.max_length(field)}
      />
      <:submit
        disabled={@preview}
        menu={@menu}
        note={
          gettext(
            "You appear in this session's list right away; the club head seats you as a speaker or the adjudicator."
          )
        }
      >
        {gettext("Register")}
      </:submit>
    </.form_for>
    """
  end
end
