defmodule CabWeb.Layouts do
  @moduledoc """
  The page shell: root (the HTML document) and app (sidenav + main
  column + footer).
  """
  use CabWeb, :html

  embed_templates "layouts/*"

  @doc """
  The app shell: left sidenav (the only navigation) + the main column
  the page fills with its chrome and body, the footer under it.

      <Layouts.app flash={@flash} current_user={@current_user}
                   club={@club} club_role={@club_role}
                   nav_session={@nav_session} active="rooms">
        <.chrome .../>
        <div class="pbody">...</div>
      </Layouts.app>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_user, :any, default: nil
  attr :club, :any, default: nil, doc: "club context for the sidenav; nil = global"
  attr :club_role, :atom, default: :public
  attr :nav_session, :any, default: nil, doc: "the club's current session (sidenav Rooms)"
  attr :active, :string, default: nil, doc: "the lit sidenav item"

  slot :inner_block, required: true

  def app(assigns)

  @doc """
  The words assets/js writes itself (ballot hints, the prep clock, the
  room card, copy buttons, the theme button), in the page's language,
  for `<meta name="cab-i18n">`. `{name}` marks a value the browser
  fills in.
  """
  def js_strings do
    %{
      "place_1" => gettext("1st"),
      "place_2" => gettext("2nd"),
      "place_3" => gettext("3rd"),
      "place_4" => gettext("4th"),
      "place_n" => gettext("{n}th"),
      "ballot_tied" =>
        gettext("Two teams share a total. BP allows no ties, so adjust the scores."),
      "ballot_ready" => gettext("Ready to submit."),
      "prep_over" => gettext("prep time is over — debate"),
      "prep_left" => gettext("prep: {time} left"),
      "card_starts" => gettext("Starts at {time}"),
      "card_motion" => gettext("MOTION"),
      "card_prep" => gettext("Prep until {time}"),
      "card_no_motion" => gettext("Motion: not published yet"),
      "card_adjudicators" => gettext("Adjudicators"),
      "card_results" => gettext("Results"),
      "card_place" => gettext("PLACE"),
      "card_side" => gettext("SIDE"),
      "card_speakers" => gettext("SPEAKERS"),
      "card_speaker_points" => gettext("SPEAKER POINTS"),
      "card_team_points" => gettext("TEAM POINTS"),
      "text_team_points" => gettext("team points: {points}"),
      "text_adjudicators" => gettext("Adjudicators: {names}"),
      "card_scan" => gettext("Scan or open"),
      "card_copied" => gettext("Copied. Paste it into the chat."),
      "card_no_copy" =>
        gettext("This browser cannot copy pictures. Right-click or hold the picture to save it."),
      "card_no_copy_text" => gettext("This browser cannot copy. Select the text and copy it."),
      "text_motion" => gettext("Motion: {motion}"),
      "text_infoslide" => gettext("Infoslide: {text}"),
      "copy" => gettext("Copy"),
      "copied" => gettext("Copied"),
      "theme_light" => gettext("Theme: light"),
      "theme_auto" => gettext("Theme: auto"),
      "theme_dark" => gettext("Theme: dark")
    }
  end
end
