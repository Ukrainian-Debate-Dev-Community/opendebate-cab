defmodule Ui.Gettext do
  @moduledoc """
  The components' own words. The apps set its locale wherever they set
  their own backend's (per request, per LiveView, per e-mail), so a
  page reads in one language.
  """
  use Gettext.Backend, otp_app: :ui
end
