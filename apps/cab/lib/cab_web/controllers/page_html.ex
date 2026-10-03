defmodule CabWeb.PageHTML do
  use CabWeb, :html

  def home(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-lg font-semibold">cab</h1>
      <%= if @current_user do %>
        <p>Signed in as {@current_user.username}</p>
        <.link href={~p"/auth/logout"}>Sign out</.link>
      <% else %>
        <.link href={~p"/auth/github"}>Sign in with GitHub</.link>
      <% end %>
    </Layouts.app>
    """
  end
end
