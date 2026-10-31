defmodule PublicWeb.CabOperator do
  @moduledoc """
  Who runs cab for this site: the texts, links and addresses cab shows
  in its footer, on its home and sign-in pages and on its account page,
  all from the tenant's `cab` keys. Public.Application hands it to cab
  at boot (`Application.put_env(:cab, :operator, PublicWeb.CabOperator)`).

  cab sets its own backend's locale per request and per LiveView, so
  the texts are given in that same language.
  """
  @behaviour CabWeb.Operator

  alias Public.Tenant

  @texts ~w(about org_text org_label signin_foot directory_title welcome tagline)a
  @links ~w(site_url org_url contact_email support_email)a

  @impl true
  def info do
    locale = Gettext.get_locale(CabWeb.Gettext)

    Map.merge(
      Map.new(@texts, &{&1, Tenant.text([:cab, &1], locale)}),
      Map.new(@links, &{&1, Tenant.get([:cab, &1])})
    )
  end
end
