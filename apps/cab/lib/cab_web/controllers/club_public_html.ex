defmodule CabWeb.ClubPublicHTML do
  use CabWeb, :html

  def show(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.chrome
        account
        current_user={@current_user}
        crumbs={[{@club.name, ~p"/c/#{@club.uuid}"}]}
        here="about"
        stage="recruiting"
        stage_kind={:ok}
      >
        <:seg
          :if={@club_role == :public and is_nil(@current_user)}
          href={~p"/auth/github"}
          primary
        >
          Request to join
        </:seg>
        <:seg
          :if={@club_role == :public and @current_user}
          href={~p"/api/v1/clubs/#{@club.uuid}/join-requests"}
          method="post"
          primary
        >
          Request to join
        </:seg>
        <:seg :if={@club_role in [:member, :owner]} href={~p"/c/#{@club.uuid}/member"}>
          Member area
        </:seg>
        <:seg :if={@club_role == :owner} href={~p"/c/#{@club.uuid}/owner"}>
          Owner area
        </:seg>
      </.chrome>

      <div class="pbody">
        <.flash_banners flash={@flash} />

        <.section title="Club" pad>
          <b id="club-name">{@club.name}</b>{if @club.city, do: " · #{@club.city}"}
        </.section>

        <.section title="History">
          <.table id="club-history" rows={@history} empty="No completed sessions yet.">
            <:col :let={event} label="Session">{event["name"]}</:col>
            <:col :let={event} label="Winner">
              <%= if event["winner"] do %>
                {event["winner"]}
                <.tag kind={:ok}>won</.tag>
              <% else %>
                —
              <% end %>
            </:col>
          </.table>
        </.section>

        <.section title="Members" pad>
          {length(@members)} member{if length(@members) != 1, do: "s"}{if head_name(@members),
            do: " · head: #{head_name(@members)}"}
          <p>Full roster is visible to members.</p>
        </.section>
      </div>
    </Layouts.app>
    """
  end

  # list_members/1 orders head first
  defp head_name([%{user: user} | _rest]), do: user.name || user.username
  defp head_name([]), do: nil
end
