defmodule CabWeb.RegistrationHTML do
  @moduledoc """
  /r/:sess - the registration form (guest or signed-in), the guest's
  personal-link page, and the registration-closed notice.
  """
  use CabWeb, :html

  import CabWeb.FormComponents,
    only: [answer_name: 1, block_type: 1, input_type: 1, placeholder: 1, prompt: 1]

  embed_templates "registration_html/*"
end
