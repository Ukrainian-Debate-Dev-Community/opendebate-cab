defmodule PublicWeb.Gettext do
  @moduledoc "The site's words in English (the msgids) and their translations."
  use Gettext.Backend, otp_app: :public
end
