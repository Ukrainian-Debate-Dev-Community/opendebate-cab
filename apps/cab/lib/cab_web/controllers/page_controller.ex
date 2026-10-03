defmodule CabWeb.PageController do
  use CabWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
