defmodule CabWeb.RegistrationHTML do
  @moduledoc """
  /r/:sess - the registration form (guest or signed-in), the guest's
  personal-link page, and the registration-closed notice.
  """
  use CabWeb, :html

  embed_templates "registration_html/*"
end
