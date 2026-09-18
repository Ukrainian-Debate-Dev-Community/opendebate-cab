defmodule CabWeb.Ui do
  @moduledoc """
  cab-specific chrome on top of the `Core.Ui` design system: the page
  shell (top bar, user menu, inlined cab2 CSS scoped under `.cab`) and
  the tournament flow strips wired to cab routes. Pure, route-free
  components (statusline, guide, status_tag) live in `Core.Ui`.
  """

  use Phoenix.Component
  use Phoenix.VerifiedRoutes, endpoint: CabWeb.Endpoint, router: CabWeb.Router

  import Core.Ui

  attr :current_user, :any, default: nil
  attr :dev_routes, :boolean, default: false
  attr :dev_users, :list, default: []
  attr :context, :any, default: nil, doc: "bar context title, e.g. tournament name"
  attr :return_to, :string, default: "/"
  attr :title, :string, required: true
  attr :subtitle, :any, default: nil
  attr :error, :any, default: nil
  attr :notice, :any, default: nil
  slot :head_tag
  slot :inner_block, required: true

  def shell(assigns) do
    ~H"""
    <style>
      .cab { --violet-900:#241333; --violet-700:#4C2A64; --violet-600:#66347E;
        --violet-500:#7F4B99; --violet-400:#9C6DB4; --violet-200:#D9C5E4;
        --violet-100:#EDE2F3; --violet-50:#F8F4FB;
        --ink:#2A2230; --muted:#7A7083; --line:#EDE7F2;
        --gold:#E0A83C; --gold-soft:#F7E8CB; --gold-dark:#B9862A;
        --ok:#2E8B6E; --ok-bg:#EAF5F0; --warn:#B4552D; --warn-bg:#FAF0EA;
        --surface:#fff; --role:#66347E; --role-soft:#EDE2F3; --radius:14px;
        font-family:"Montserrat",system-ui,sans-serif; color:var(--ink);
        background:#FDFCFE; line-height:1.55; font-size:15px;
        min-height:100vh; margin:0; }
      .cab *, .cab *::before, .cab *::after { box-sizing:border-box; }
      .cab a { color:var(--violet-600); }
      .cab .bar { display:flex; align-items:center; gap:16px; padding:10px 18px;
        background:rgba(253,252,254,.92); border-bottom:1px solid var(--line);
        position:sticky; top:0; z-index:40; }
      .cab .bar .brand { font-weight:800; font-size:.98rem; display:flex; align-items:center;
        gap:9px; color:var(--ink); text-decoration:none; }
      .cab .bar .brand .dot { width:25px; height:25px; border-radius:8px;
        background:var(--violet-600); color:#fff; display:inline-flex; align-items:center;
        justify-content:center; font-size:.62rem; font-weight:800; }
      .cab .bar .ctx { font-weight:800; font-size:.95rem; }
      .cab .usermenu { position:relative; margin-left:auto; }
      .cab .usermenu summary { list-style:none; display:flex; align-items:center; gap:9px;
        cursor:pointer; font-size:.82rem; font-weight:600; color:var(--ink);
        padding:5px 10px; border-radius:999px; }
      .cab .usermenu summary::-webkit-details-marker { display:none; }
      .cab .usermenu summary:hover { background:var(--violet-50); }
      .cab .usermenu .avatar { width:28px; height:28px; font-size:.62rem; border-radius:50%;
        background:var(--violet-500); color:#fff; display:inline-flex; align-items:center;
        justify-content:center; font-weight:800; }
      .cab .userdrop { position:absolute; top:calc(100% + 6px); right:0; background:#fff;
        border:1px solid var(--line); border-radius:12px; min-width:260px; padding:6px;
        box-shadow:0 10px 30px rgba(36,19,51,.14); z-index:50; }
      .cab .userdrop a { display:block; padding:8px 12px; border-radius:8px; font-size:.82rem;
        color:var(--ink); text-decoration:none; }
      .cab .userdrop a:hover { background:var(--violet-50); }
      .cab .userdrop .dhead { padding:6px 12px; font-size:.66rem; font-weight:800;
        color:var(--muted); text-transform:uppercase; }
      .cab .userdrop form { padding:6px 10px; display:flex; gap:6px; }
      .cab .pubwrap { margin:0 auto; padding:22px 22px 60px; max-width:980px; }
      .cab .h1 { font-size:1.35rem; letter-spacing:-.02em; font-weight:800; margin:0; }
      .cab .rolehead { display:flex; align-items:center; gap:12px; margin-bottom:14px;
        flex-wrap:wrap; }
      .cab .section-title { font-size:.7rem; letter-spacing:.14em; text-transform:uppercase;
        color:var(--muted); margin:26px 0 12px; font-weight:700; }
      .cab .text-muted { color:var(--muted); }
      .cab .f-help { font-size:.78rem; color:var(--muted); }
      .cab .btn { display:inline-block; padding:10px 18px; border-radius:999px;
        font-weight:700; font-size:.85rem; text-decoration:none; border:none;
        cursor:pointer; font-family:inherit; line-height:1.3; }
      .cab .btn:disabled { opacity:.45; cursor:not-allowed; }
      .cab .btn--primary { background:var(--violet-600); color:#fff; }
      .cab .btn--cta { background:var(--gold); color:var(--violet-900); }
      .cab .btn--soft { background:var(--violet-100); color:var(--violet-700); }
      .cab .btn--sm { padding:6px 13px; font-size:.77rem; }
      .cab .tag { font-size:.68rem; font-weight:700; border-radius:999px; padding:4px 11px;
        display:inline-block; white-space:nowrap; }
      .cab .tag--ok { background:var(--ok-bg); color:var(--ok); }
      .cab .tag--warn { background:var(--warn-bg); color:var(--warn); }
      .cab .tag--info { background:var(--violet-50); color:var(--violet-600); }
      .cab .tag--muted { background:#F4F1F6; color:var(--muted); }
      .cab .tag--gold { background:var(--gold-soft); color:var(--gold-dark); font-weight:800; }
      .cab .card { background:var(--surface); border:1px solid var(--line);
        border-radius:var(--radius); overflow:hidden;
        box-shadow:0 2px 16px rgba(56,32,78,.05); margin-bottom:14px; }
      .cab .card__head { display:flex; align-items:center; justify-content:space-between;
        gap:12px; padding:14px 18px; border-bottom:1px solid var(--line); font-weight:700; }
      .cab .card__pad { padding:16px 18px; }
      .cab .cardgrid { display:grid; grid-template-columns:repeat(auto-fit,minmax(260px,1fr));
        gap:14px; }
      .cab .kv { display:flex; justify-content:space-between; padding:4px 0; font-size:.84rem; }
      .cab .kv span:first-child { color:var(--muted); }
      .cab .scroll-x { overflow-x:auto; }
      .cab table.tbl { width:100%; border-collapse:collapse; font-size:.87rem; }
      .cab .tbl th { text-align:left; padding:11px 16px; font-weight:700; font-size:.68rem;
        letter-spacing:.1em; text-transform:uppercase; white-space:nowrap;
        color:var(--violet-600); border-bottom:2px solid var(--violet-100); }
      .cab .tbl td { padding:12px 16px; border-top:1px solid var(--line); }
      .cab .tbl tbody tr:first-child td { border-top:none; }
      .cab .tbl tbody tr:hover { background:var(--violet-50); }
      .cab .tbl td.rank { font-weight:800; color:var(--violet-500); width:44px; }
      .cab .progressline { display:flex; height:32px; border-radius:999px; overflow:hidden;
        border:1px solid var(--line); background:#fff; margin:4px 0 2px; }
      .cab .pseg { flex:1; display:flex; align-items:center; justify-content:center;
        font-size:.68rem; font-weight:800; color:var(--muted); text-decoration:none;
        border-left:1px solid var(--line); }
      .cab .pseg:first-child { border-left:none; }
      .cab .pseg.done { background:var(--role); color:#fff; }
      .cab .pseg.live { background:var(--gold); color:var(--violet-900); }
      .cab .pseg.sel { outline:2px solid var(--violet-400); outline-offset:-2px; }
      .cab .f-row { display:flex; gap:10px; align-items:center; flex-wrap:wrap; }
      .cab .f-label { font-size:.72rem; font-weight:800; letter-spacing:.1em;
        text-transform:uppercase; color:var(--role); margin-bottom:8px; display:block; }
      .cab .input, .cab select, .cab textarea { padding:9px 14px; border:1.5px solid var(--line);
        border-radius:14px; font:inherit; font-size:.85rem; background:#fff; color:var(--ink); }
      .cab .input:focus, .cab textarea:focus { outline:none; border-color:var(--violet-400); }
      .cab input.input { border-radius:999px; }
      .cab .alert { display:flex; gap:10px; border-radius:12px; padding:12px 16px;
        font-size:.85rem; align-items:center; margin:10px 0; flex-wrap:wrap; }
      .cab .alert--ok { background:var(--ok-bg); color:#1E5C48; }
      .cab .alert--warn { background:var(--warn-bg); color:#8A3F1E; }
      .cab .alert--info { background:var(--violet-50); color:#38204E; }
      .cab .motionline { display:flex; align-items:center; gap:12px; background:var(--surface);
        border:1px solid var(--line); border-radius:12px; padding:10px 16px; margin:10px 0 14px;
        flex-wrap:wrap; }
      .cab .motionline .m { font-size:.92rem; font-weight:700; }
      .cab .ballot-team { display:grid; grid-template-columns:1fr auto; gap:10px 16px;
        padding:14px 18px; border-top:1px solid var(--line); align-items:center; }
      .cab .ballot-team:first-child { border-top:none; }
      .cab .ballot-team h4 { margin:0; }
      .cab .spk-row { grid-column:1/-1; display:grid; grid-template-columns:1fr 1fr; gap:10px; }
      .cab .spk { display:flex; align-items:center; gap:10px; font-size:.8rem; }
      .cab .spk .nm { flex:1; }
      .cab .spk input { width:72px; padding:6px 8px; border:1.5px solid var(--line);
        border-radius:8px; font:inherit; font-size:.8rem; text-align:center; }
      .cab .chip { display:inline-block; background:#fff; border:1.5px solid var(--violet-200);
        border-radius:999px; padding:5px 12px; font-size:.8rem; font-weight:600; }
    </style>
    <div class="cab">
      <div class="bar">
        <a class="brand" href={~p"/"}><span class="dot">C</span> cab</a>
        <span :if={@context} class="ctx">{@context}</span>
        <details :if={@dev_routes} class="usermenu">
          <summary>
            <span :if={@current_user} class="avatar">{initials(@current_user.username)}</span>
            <span :if={@current_user}>{@current_user.username}</span>
            <span :if={is_nil(@current_user)} class="tag tag--warn">not signed in — pick a user</span>
            ▾
          </summary>
          <div class="userdrop">
            <div class="dhead">switch user (dev only)</div>
            <a
              :for={user <- @dev_users}
              href={"/dev/switch-user?username=#{user.username}&return_to=#{@return_to}"}
              style={
                @current_user && @current_user.username == user.username &&
                  "font-weight:800;color:var(--violet-700);"
              }
            >
              {user.username}
            </a>
            <form action="/dev/switch-user" method="get">
              <input type="hidden" name="return_to" value={@return_to} />
              <input
                class="input"
                type="text"
                name="username"
                placeholder="new user…"
                style="flex:1;"
              />
              <button class="btn btn--soft btn--sm" type="submit">Go</button>
            </form>
          </div>
        </details>
        <span :if={!@dev_routes} class="usermenu" style="font-size:.82rem; font-weight:600;">
          <span :if={@current_user}>{@current_user.username}</span>
          <span :if={is_nil(@current_user)} class="text-muted">not signed in</span>
        </span>
      </div>

      <div class="pubwrap">
        <div class="rolehead">
          <h1 class="h1">{@title}</h1>
          {render_slot(@head_tag)}
        </div>
        <p :if={@subtitle} class="text-muted" style="margin:-8px 0 14px; font-size:.86rem;">
          {@subtitle}
        </p>
        <div :if={@error} class="alert alert--warn"><b>!</b> <span>{@error}</span></div>
        <div :if={@notice} class="alert alert--ok"><b>✓</b> <span>{@notice}</span></div>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  cab2 tdFlow: rounds strip (R1..Rn, Final) plus, when `seq` names a
  preliminary round, the four-step strip for it. `steps_done` is how
  many of check-in / draw+motion / ballots / done are finished;
  `active` highlights the step of the current page. Both strips are
  rendered through `statusline/1`.
  """
  attr :event_id, :any, required: true
  attr :rounds, :list, default: []
  attr :seq, :any, default: nil
  attr :steps_done, :integer, default: 0
  attr :active, :any, default: nil

  def td_flow(assigns) do
    ~H"""
    <.statusline items={round_items(@event_id, @rounds, @seq)} />
    <.statusline
      :if={@seq && current_round_name(@rounds, @seq) != "Final"}
      items={step_items(@event_id, @seq, @steps_done, @active)}
      style="margin-top:6px;"
    />
    """
  end

  defp round_items(event_id, rounds, seq) do
    items =
      Enum.map(rounds, fn round ->
        %{
          label: if(round["name"] == "Final", do: "Final", else: "R#{round["sequence"]}"),
          state: round_state(round, rounds),
          sel: seq == round["sequence"],
          href: round_link(event_id, round)
        }
      end)

    # The upcoming-Final placeholder only applies to multi-round
    # tournaments; one-round events (club sessions) have no final.
    if Enum.any?(rounds, &(&1["name"] == "Final")) or length(rounds) < 2 do
      items
    else
      items ++ [%{label: "Final"}]
    end
  end

  defp step_items(event_id, seq, steps_done, active) do
    step_defs()
    |> Enum.with_index()
    |> Enum.map(fn {{label, step_key}, index} ->
      %{
        label: label,
        state: step_state(index, steps_done),
        sel: active == step_key && step_key != nil,
        href: step_key && step_href(event_id, seq, step_key)
      }
    end)
  end

  defp step_defs do
    [{"check-in", "checkin"}, {"draw + motion", "draw"}, {"ballots", "ballots"}, {"done", nil}]
  end

  defp step_href(event_id, seq, "checkin"), do: ~p"/t/#{event_id}/r/#{seq}/checkin"
  defp step_href(event_id, seq, "draw"), do: ~p"/t/#{event_id}/r/#{seq}/draw"
  defp step_href(event_id, seq, "ballots"), do: ~p"/t/#{event_id}/r/#{seq}/ballots"

  defp step_state(index, done) when index < done, do: "done"
  defp step_state(index, done) when index == done, do: "live"
  defp step_state(_index, _done), do: nil

  defp round_state(round, rounds) do
    cond do
      round["status"] == "completed" -> "done"
      first_open?(round, rounds) -> "live"
      true -> nil
    end
  end

  defp first_open?(round, rounds) do
    Enum.find(rounds, &(&1["status"] != "completed")) == round
  end

  defp current_round_name(rounds, seq) do
    case Enum.find(rounds, &(&1["sequence"] == seq)) do
      nil -> nil
      round -> round["name"]
    end
  end

  defp round_link(event_id, %{"name" => "Final", "sequence" => seq}),
    do: ~p"/t/#{event_id}/r/#{seq}/ballots"

  defp round_link(event_id, %{"sequence" => seq}),
    do: ~p"/t/#{event_id}/r/#{seq}/checkin"

  defp initials(username) do
    username
    |> String.split(~r/[\s_-]+/, trim: true)
    |> Enum.map(&String.first/1)
    |> Enum.take(2)
    |> Enum.join()
    |> String.upcase()
  end
end
