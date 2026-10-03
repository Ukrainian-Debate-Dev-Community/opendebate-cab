defmodule CabWeb.ClubPublicHTML do
  use CabWeb, :html

  def show(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 id="club-name">{@club.name}</h1>
      <p :if={@club.city}>{@club.city}</p>

      <p>
        <.link :if={@club_role in [:member, :owner]} href={~p"/c/#{@club.uuid}/member"}>
          Member area
        </.link>
        <.link :if={@club_role == :owner} href={~p"/c/#{@club.uuid}/owner"}>
          Owner area
        </.link>
      </p>

      <h2>History</h2>
      <p :if={@history == []}>No completed sessions yet.</p>
      <table :if={@history != []} id="club-history">
        <thead>
          <tr>
            <th>Session</th>
            <th>Winner</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={event <- @history}>
            <td>{event["name"]}</td>
            <td>{event["winner"] || "—"}</td>
          </tr>
        </tbody>
      </table>
    </Layouts.app>
    """
  end
end
