defmodule CabWeb.StandingsHTML do
  use CabWeb, :html

  # the global standings page; the club page (ClubPublicHTML) reuses
  # the components below so both scopes render the SAME four tabs
  def show(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} active="standings">
      <.chrome here="standings"></.chrome>
      <.standings_tabs base="/standings" active={@tab} />

      <div class="pbody">
        <.flash_banners flash={@flash} />
        <.standings_body tab={@tab} scope={@scope} rows={@rows} club={@club} />
      </div>
    </Layouts.app>
    """
  end

  @doc """
  The standings tabs (pages-v6 .selrow), shared by both scopes —
  the Clubs tab is GLOBAL-ONLY (a club comparing clubs inside its
  own scope makes no sense).
  """
  attr :base, :string, required: true
  attr :active, :string, required: true
  attr :clubs_tab, :boolean, default: true

  def standings_tabs(assigns) do
    ~H"""
    <.selrow
      id="standings-tabs"
      active={@active}
      tabs={
        [
          {"teams", "Teams", "#{@base}/teams"},
          {"speakers", "Speakers", "#{@base}/speakers"},
          {"judges", "Judges", "#{@base}/judges"}
        ] ++ if(@clubs_tab, do: [{"clubs", "Clubs", "#{@base}/clubs"}], else: [])
      }
    />
    """
  end

  @doc """
  One standings tab's content — RULE 0: the engine's calculated
  standings verbatim (name + total_points) for ONE session, judges
  as a plain chair count, clubs as plain counts. `club` scopes the
  heading and the previous-sessions link; nil = global.
  """
  attr :tab, :string, required: true
  attr :scope, :any, default: nil, doc: "%{session, club, event} or nil (none finished)"
  attr :rows, :list, required: true
  attr :club, :any, default: nil
  attr :archive, :list, default: nil
  attr :base, :string, default: nil

  def standings_body(assigns) do
    ~H"""
    <%= if @tab == "clubs" do %>
      <.section title="Clubs — plain counts only">
        <.table id="standings-clubs" rows={@rows} rank empty="No clubs yet.">
          <:col :let={row} label="Club">
            <.link href={~p"/c/#{row.club.uuid}"}>{row.club.name}</.link>
          </:col>
          <:col :let={row} label="City">{row.club.city || "—"}</:col>
          <:col :let={row} label="Members" num>{row.members}</:col>
          <:col :let={row} label="Sessions" num>{row.sessions}</:col>
          <:col :let={row} label="Rooms" num>{row.rooms}</:col>
        </.table>
      </.section>
    <% else %>
      <%= if @scope do %>
        <.section title={tab_label(@tab)}>
          <div class="pad scope-card">
            <p>
              session: <b>{@scope.session.name}</b>, {Calendar.strftime(scope_date(@scope), "%-d %b")} · {@scope.club.name}{if assigns[
                                                                                                                                 :archive
                                                                                                                               ],
                                                                                                                               do:
                                                                                                                                 " (latest finished)"}
            </p>
            <div :if={earlier_rows(assigns) != []} class="flinks">
              <span class="mut">earlier:</span>
              <.link
                :for={row <- earlier_rows(assigns)}
                href={"#{@base}/#{@tab}?session=#{row.session_uuid}"}
              >
                {row.name} · {Calendar.strftime(row.date, "%-d %b")}
              </.link>
            </div>
          </div>
          <.table
            id={"standings-#{@tab}"}
            rows={@rows}
            rank
            empty="The engine returned no standings for this session."
          >
            <:col :let={row} :if={@tab == "teams"} label="Team">{row["name"]}</:col>
            <:col :let={row} :if={@tab == "speakers"} label="Speaker">{row["name"]}</:col>
            <:col :let={row} :if={@tab in ["teams", "speakers"]} label="Points" num>
              {row["total_points"]}
            </:col>
            <:col :let={row} :if={@tab == "judges"} label="Judge">{row["name"]}</:col>
            <:col :let={row} :if={@tab == "judges"} label="Rooms judged" num>
              {row["rooms_judged"]}
            </:col>
            <:col :let={row} :if={@tab == "judges"} label="Avg feedback" num>
              {row["avg_feedback"] || "—"}
            </:col>
          </.table>
        </.section>
      <% else %>
        <.section title={tab_label(@tab)} pad>
          No finished session yet.
          <p>Standings show one session's engine results — the latest finished one.</p>
        </.section>
      <% end %>
    <% end %>
    """
  end

  # the archive minus the shown session — the selector links on the
  # scope card (club scope passes archive + base; global passes none)
  defp earlier_rows(%{archive: archive, scope: scope}) when is_list(archive) do
    shown = scope && scope.session.uuid
    Enum.reject(archive, &(&1.session_uuid == shown))
  end

  defp earlier_rows(_assigns), do: []

  defp scope_date(%{session: session}), do: session.scheduled_at || session.inserted_at

  defp tab_label("teams"), do: "Teams"
  defp tab_label("speakers"), do: "Speakers"
  defp tab_label("judges"), do: "Judges"
  defp tab_label("clubs"), do: "Clubs"
end
