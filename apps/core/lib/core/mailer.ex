defmodule Core.Mailer do
  @moduledoc """
  The platform's one mailer. Each app writes its own e-mails and
  delivers them here; the adapter (local preview, test capture or SMTP)
  is set once in config.
  """
  use Swoosh.Mailer, otp_app: :core
end
