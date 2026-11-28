defmodule CabWeb.Tour do
  @moduledoc """
  The guided tour (`/tour`): an autoplay walkthrough of cab for
  newcomers and demos in three parts - a session played from start to
  finish, the screen passing between the club head, a speaker and an
  adjudicator as each of them acts; the club around it; and more. The
  tour is data: steps of

    * `chapter`, `text` - the chapter and the caption (shown beside the
      spotlight);
    * `frame` - one of `CabWeb.Tour.Pages`' demo pages (nil: a title
      card), `target` - the CSS selector spotlighted on it (nil: the
      whole page);
    * `set` - `[{selector, value}]` already on the page when the step
      opens (what earlier steps typed); `fill` - what the player types
      (or picks) into the page; `click` - the selector it then clicks;
      the next step shows what the click led to;
    * `as` - whose eyes the page is seen through.

  Every step's frame, target, fields and click are checked by the tour
  test, so a page that changes shape fails it - the tour doubles as a
  consistency check.
  """
  use Gettext, backend: CabWeb.Gettext

  @doc "The tour."
  def get, do: tour()

  @doc "The chapters of the tour, in order, each once."
  def chapters(tour), do: tour.steps |> Enum.map(& &1.chapter) |> Enum.uniq()

  @doc """
  How long a step holds, in milliseconds: reading (60 ms a character,
  at least 4 s), typing (45 ms a character after a short pause) and a
  click. The player keeps the same sums.
  """
  def hold(step) do
    reading = max(4000, String.length(step.text) * 60)

    typing =
      Enum.sum(Enum.map(step.fill, fn {_selector, value} -> 400 + String.length(value) * 45 end))

    reading + typing + if(step.click, do: 1800, else: 0)
  end

  @doc "Which page a frame is, as the tour names it beside whose screen it is."
  def where("me-" <> _rest), do: gettext("My page")
  def where("guest-hub"), do: gettext("the personal link page")
  def where("owner-club"), do: gettext("the club settings")
  def where("owner-members"), do: gettext("the members page")
  def where("owner-form"), do: gettext("the registration form")
  def where("owner-" <> _stage), do: gettext("the spar page")
  def where("clubs"), do: gettext("the club list")
  def where("club-visitor"), do: gettext("the club page")
  def where("join"), do: gettext("the join form")
  def where("results"), do: gettext("the results page")
  def where(_frame), do: nil

  @ballot ~w(og:PM og:DPM oo:LO oo:DLO cg:MG cg:GW co:MO co:OW)

  # the ballot's eight scores, in order
  defp scores(values) do
    for {slot, value} <- Enum.zip(@ballot, values) do
      [side, role] = String.split(slot, ":")
      {~s(#now-ballot-71 input[name="ballot[#{side}][#{role}][score]"]), value}
    end
  end

  # three parts: one session played from start to finish (the head,
  # a speaker, an adjudicator taking turns), the club around it (a
  # newcomer joins, the head runs the club), and more of what cab does
  defp tour do
    daria = gettext("Daria, the club head")
    anna = gettext("Anna, a speaker")
    petro = gettext("Petro, an adjudicator")
    mark = gettext("Mark, a newcomer")
    session = gettext("Debating a spar")
    clubs = gettext("Clubs")
    more = gettext("And more")

    %{
      title: gettext("cab, a guided tour"),
      lead:
        gettext(
          "How a debate club runs on cab: a spar debated from start to finish, the club around it, and the rest."
        ),
      steps: [
        card(
          gettext("Welcome"),
          gettext(
            "Riverside Debate Club meets on Thursdays. Watch a spar through the head who runs it, a speaker and an adjudicator; then the club itself; then the rest."
          )
        ),

        # ---- 1. playing a session --------------------------------
        card(
          session,
          gettext(
            "One Thursday night, from opening the spar to the results. Daria runs the club, Anna debates, Petro adjudicates."
          )
        ),
        step(
          session,
          "owner-club",
          "#open-session-form",
          gettext("Daria opens Thursday's spar: a name, the date, the format and a place limit."),
          as: daria,
          fill: [{"#open-session-form input[name=name]", "Thursday night"}],
          click: ~s(button[form="open-session-form"])
        ),
        step(
          session,
          "owner-registration",
          "#shared-registration-url",
          gettext(
            "The spar takes sign-ups. Daria shares one link in the club chat; members register on My page, guests from the club page."
          ),
          as: daria
        ),
        step(
          session,
          "me-register",
          "#me-registration",
          gettext(
            "Anna is a member: Thursday's spar shows on her My page, where she does everything from here on."
          ),
          as: anna,
          click: "#open-sessions button[phx-click=open_register]"
        ),
        step(
          session,
          "me-register-form",
          "#me-register-form",
          gettext(
            "The club's question comes prefilled with her saved answer. One click and she is in."
          ),
          as: anna,
          click: "#me-register-form button[type=submit]"
        ),
        step(
          session,
          "me-registered",
          "#open-sessions",
          gettext("Registered, with Cancel if her plans change."),
          as: anna
        ),
        step(
          session,
          "owner-registration",
          "#session-people",
          gettext(
            "Sign-ups reach Daria live - members, people she added by hand, guests with a personal link - and on the night she checks in who is here."
          ),
          as: daria
        ),
        step(
          session,
          "owner-registration",
          ".steps",
          gettext(
            "A spar moves through Check-in, Draw, Debates and Finished. Everyone is checked in: Daria goes to the Draw."
          ),
          as: daria,
          click: ".steps li:nth-child(2) a"
        ),
        step(
          session,
          "owner-rooms",
          ".dnd",
          gettext(
            "She makes the draw - Anna into Opening Opposition, Petro into the chair - and starts the spar."
          ),
          as: daria,
          click: ~s(button[form="allocator-form"])
        ),
        step(
          session,
          "me-now",
          "[id^=now-draw-]",
          gettext("Without a reload Anna's My page shows her room, her side and her partner."),
          as: anna
        ),
        step(
          session,
          "me-chair",
          "#now-motion-71",
          gettext(
            "Petro's My page says he chairs room 1. He types the motion, an infoslide and a keyword, and publishes it."
          ),
          as: petro,
          fill: [
            {"#now-motion-text-71", "This House would ban homework in primary schools"},
            {"#now-infoslide-71",
             "In several countries primary schools have dropped homework altogether."},
            {"#now-keyword-71", "education"}
          ],
          click: "#now-motion-71 button[type=submit]"
        ),
        step(
          session,
          "me-now",
          "#now-motion-box-71",
          gettext(
            "At once the motion is on Anna's page, and 15 minutes of prep count down for the whole room."
          ),
          as: anna
        ),
        step(
          session,
          "me-ballot",
          "#now-ballot-71",
          gettext(
            "After the debate Petro fills the ballot: a score for each speaker; the places follow from the team totals."
          ),
          as: petro,
          fill: scores(~w(76 75 75 76 74 73 72 71))
        ),
        step(
          session,
          "me-ballot",
          "#now-ballot-71",
          gettext(
            "Two teams on the same total: cab will not take a tie. Petro raises the leader's score, and the ballot is ready."
          ),
          as: petro,
          set: scores(~w(76 75 75 76 74 73 72 71)),
          fill: [{~s(#now-ballot-71 input[name="ballot[oo][LO][score]"]), "77"}],
          click: ~s(button[form="now-ballot-71"])
        ),
        step(
          session,
          "me-result",
          "#now-result-71",
          gettext(
            "Anna sees the result straight away: her team is first, with its speaker points."
          ),
          as: anna
        ),
        step(
          session,
          "me-result",
          "#now-feedback-71",
          gettext("Before the spar is finished, Anna's team rates the adjudicator."),
          as: anna,
          fill: [
            {"#now-feedback-71 input[name=accuracy]", "8"},
            {"#now-feedback-71 input[name=reasoning]", "7"},
            {"#now-feedback-71 textarea[name=discussion]",
             "A clear call, and useful advice on rebuttal."}
          ],
          click: "#now-feedback-71 button[type=submit]"
        ),
        step(
          session,
          "me-feedback-sent",
          "#now-feedback-sent-71",
          gettext("Sent. Petro reads it, without the team's name, once the spar is over."),
          as: anna
        ),
        step(
          session,
          "owner-debates",
          "#session-rooms",
          gettext("Daria follows every room: motions out, ballots in, feedback arriving."),
          as: daria
        ),
        step(
          session,
          "owner-debates",
          "#feedback-missing",
          gettext(
            "Two teams have not rated their adjudicator yet. Finishing closes feedback, so Finish asks first."
          ),
          as: daria,
          click: ~s(.seg a[href$="/finish"])
        ),
        step(
          session,
          "results",
          "[id^=results-card-]",
          gettext(
            "Finished: the winners are recorded and the results are public, ready to paste into the club chat."
          ),
          as: gettext("any visitor")
        ),

        # ---- 2. clubs ----------------------------------------------
        card(
          clubs,
          gettext(
            "The club around the spars: someone new finds it and joins, and Daria keeps it running."
          )
        ),
        step(
          clubs,
          "clubs",
          "#clubs-directory tbody tr",
          gettext(
            "Mark wants to start debating. Every club on cab is listed with its next spar; he picks Riverside."
          ),
          as: mark,
          click: "#clubs-directory tbody tr a"
        ),
        step(
          clubs,
          "club-visitor",
          ".page-head",
          gettext("The club's page: who they are and when they meet. Mark asks to join."),
          as: mark,
          click: ".chrome .seg a"
        ),
        step(
          clubs,
          "join",
          "#join-request-form",
          gettext(
            "The club asks one question. His answer is saved, so he will not type it again when he registers."
          ),
          as: mark,
          fill: [{~s(#join-request-form input[value="Up to a year"]), "Up to a year"}],
          click: "#join-request-form button[type=submit]"
        ),
        step(
          clubs,
          "me-pending",
          "#my-clubs",
          gettext("On his My page the request waits for the club head."),
          as: mark
        ),
        step(
          clubs,
          "owner-members",
          "#join-requests",
          gettext("Daria sees the request with Mark's answer, and approves it. He is a member."),
          as: daria,
          click: ~s(#join-requests a[href$="/approve"])
        ),
        step(
          clubs,
          "owner-members",
          "#members-list",
          gettext("Her members, each with their saved answers."),
          as: daria
        ),
        step(
          clubs,
          "owner-form",
          "#guest-form-editor",
          gettext(
            "The club's own questions: who is asked what. Members answer once; their answers come prefilled after that."
          ),
          as: daria
        ),
        step(
          clubs,
          "owner-club",
          "#club-profile-form",
          gettext("And the club's profile: what visitors read on its page."),
          as: daria
        ),

        # ---- 3. and more -------------------------------------------
        card(
          more,
          gettext("A few more things cab does for each of them.")
        ),
        step(
          more,
          "guest-hub",
          "[id^=now-draw-]",
          gettext(
            "Guests need no account: a personal link opens the same page for their spar - the seat, the motion and, for a guest adjudicator, the ballot."
          ),
          as: gettext("Greta, a guest")
        ),
        step(
          more,
          "me-on-me",
          "[id^=feedback-on-me-]",
          gettext(
            "After the spar Petro reads each team's feedback on his call - without the team's name - and his average."
          ),
          as: petro
        ),
        step(
          more,
          "me-figures",
          "#me-stats",
          gettext(
            "Week after week Anna's My page keeps her figures, straight from the debate engine, one format at a time."
          ),
          as: anna
        ),
        step(
          more,
          "me-figures",
          "#me-history",
          gettext("And every spar she debated or adjudicated."),
          as: anna
        ),
        step(
          more,
          "owner-finished",
          "#session-picker",
          gettext(
            "Daria picks any of the club's spars here. A finished one can be reopened to fix a ballot, then finished again."
          ),
          as: daria
        ),
        %{
          card(
            gettext("That's the tour"),
            gettext(
              "Thanks for watching. Find a club to debate with, or sign in to see your own page."
            )
          )
          | finale: true
        }
      ]
    }
  end

  defp card(chapter, text), do: step(chapter, nil, nil, text)

  defp step(chapter, frame, target, text, opts \\ []) do
    %{
      chapter: chapter,
      frame: frame,
      target: target,
      text: text,
      set: Keyword.get(opts, :set, []),
      fill: Keyword.get(opts, :fill, []),
      click: Keyword.get(opts, :click),
      as: Keyword.get(opts, :as),
      finale: false
    }
  end
end
