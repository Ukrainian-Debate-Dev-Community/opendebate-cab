defmodule PublicWeb.CabOperatorTest do
  use PublicWeb.ConnCase

  alias PublicWeb.CabOperator

  test "the site hands cab its operator" do
    Application.delete_env(:cab, :operator)
    Public.Application.hand_cab_operator()
    assert Application.get_env(:cab, :operator) == CabOperator
  end

  test "the texts come from the tenant in cab's locale, the links and addresses stay" do
    en = Gettext.with_locale(CabWeb.Gettext, "en", &CabOperator.info/0)
    ua = Gettext.with_locale(CabWeb.Gettext, "uk", &CabOperator.info/0)

    assert en.about == "League cab about"
    assert en.org_text == "League cab org text"
    assert en.org_label == "League cab org label"
    assert en.signin_foot == "League cab signin foot"
    assert en.directory_title == "League cab directory title"
    assert en.welcome == "League cab welcome"
    assert en.tagline == "League cab tagline"

    for key <- ~w(about org_text org_label signin_foot directory_title welcome tagline)a do
      assert ua[key] == "UK " <> en[key]
    end

    for key <- [:site_url, :org_url, :contact_email, :support_email] do
      assert ua[key] == en[key]
    end

    assert en.site_url == "https://league.example.org"
    assert en.org_url == "https://league.example.org/about"
    assert en.contact_email == "office@example.org"
    assert en.support_email == "support@example.org"
  end

  defp cab_page(path, headers \\ []) do
    headers
    |> Enum.reduce(build_conn(), fn {k, v}, conn -> put_req_header(conn, k, v) end)
    |> Phoenix.ConnTest.dispatch(CabWeb.Endpoint, :get, path)
    |> html_response(200)
  end

  test "cab's pages show them in the visitor's language" do
    assert cab_page("/signin") =~ "League cab signin foot"
    assert cab_page("/signin", [{"accept-language", "uk"}]) =~ "UK League cab signin foot"

    footer = cab_page("/policy")
    assert footer =~ "League cab org text"
    assert footer =~ "League cab about"
    assert footer =~ "mailto:office@example.org"

    footer = cab_page("/policy", [{"accept-language", "uk"}])
    assert footer =~ "UK League cab org text"
    assert footer =~ "UK League cab about"
    refute footer =~ ">League cab org text"
  end
end
