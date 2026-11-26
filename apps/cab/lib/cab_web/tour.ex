defmodule CabWeb.Tour do
  @moduledoc """
  The guided tour (`/tour`): an autoplay walkthrough of cab for
  newcomers and demos - one club night told in order, the screen
  passing between the club head, a speaker and an adjudicator as each
  of them acts. The tour is data: steps of

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

  @ballot ~w(og:PM og:DPM oo:LO oo:DLO cg:MG cg:GW co:MO co:OW)

  # the ballot's eight scores, in order
  defp scores(values) do
    for {slot, value} <- Enum.zip(@ballot, values) do
      [side, role] = String.split(slot, ":")
      {~s(#now-ballot-71 input[name="ballot[#{side}][#{role}][score]"]), value}
    end
  end

  # one Thursday night at Riverside Debate Club, told in order through
  # the three people who make it: Daria runs the club, Anna debates,
  # Petro adjudicates
  defp tour do
    daria = gettext("Daria, the club head")
    anna = gettext("Anna, a speaker")
    petro = gettext("Petro, an adjudicator")

    %{
      title: gettext("One club night on cab"),
      lead:
        gettext(
          "A Thursday night at a debate club, through the eyes of the head who runs it, a speaker and an adjudicator."
        ),
      steps: [
        card(
          gettext("Welcome"),
          gettext(
            "One Thursday night at Riverside Debate Club, through three people: Daria runs the club, Anna comes to debate, Petro adjudicates. Watch the night from all three sides."
          )
        ),
        step(
          gettext("Opening the night"),
          "owner-club",
          "#open-session-form",
          gettext(
            "Daria opens Thursday's session: a name, the date, the format and a place limit."
          ),
          as: daria,
          fill: [{"#open-session-form input[name=name]", "Thursday night"}],
          click: ~s(button[form="open-session-form"])
        ),
        step(
          gettext("Opening the night"),
          "owner-registration",
          "#shared-registration-url",
          gettext(
            "The session takes sign-ups. Daria shares one link in the club chat; members register on My page, guests from the club page."
          ),
          as: daria
        ),
        step(
          gettext("Anna finds the club"),
          "clubs",
          "#clubs-directory tbody tr",
          gettext(
            "Anna wants to debate. Every club on cab is listed with its next session; she picks Riverside."
          ),
          as: anna,
          click: "#clubs-directory tbody tr a"
        ),
        step(
          gettext("Anna finds the club"),
          "club-visitor",
          ".chrome .seg",
          gettext("The club's page: who they are and when they meet. Anna asks to join."),
          as: anna,
          click: ".chrome .seg a"
        ),
        step(
          gettext("Anna finds the club"),
          "join",
          "#join-request-form",
          gettext(
            "The club asks one question. Her answer is saved, so she will not type it again."
          ),
          as: anna,
          fill: [{~s(#join-request-form input[value="Up to a year"]), "Up to a year"}],
          click: "#join-request-form button[type=submit]"
        ),
        step(
          gettext("Anna finds the club"),
          "me-pending",
          "#my-clubs tbody tr",
          gettext("On her My page the request waits for the club head."),
          as: anna
        ),
        step(
          gettext("Daria approves"),
          "owner-members",
          "#join-requests",
          gettext("Daria sees the request with Anna's answer, and approves it."),
          as: daria,
          click: ~s(#join-requests a[href$="/approve"])
        ),
        step(
          gettext("Anna registers"),
          "me-register",
          "#me-registration",
          gettext(
            "Anna is a member now: Thursday's session shows on her My page, where she does everything from here on."
          ),
          as: anna,
          click: "#open-sessions button[phx-click=open_register]"
        ),
        step(
          gettext("Anna registers"),
          "me-register-form",
          "#me-register-form",
          gettext(
            "The club's question comes prefilled with her saved answer. One click and she is in."
          ),
          as: anna,
          click: "#me-register-form button[type=submit]"
        ),
        step(
          gettext("Anna registers"),
          "me-registered",
          "#open-sessions tbody tr",
          gettext("Registered, with Cancel if her plans change."),
          as: anna
        ),
        step(
          gettext("Seating the rooms"),
          "owner-registration",
          "#session-people",
          gettext(
            "Sign-ups reach Daria live: members, people she added by hand, guests with their own personal link."
          ),
          as: daria
        ),
        step(
          gettext("Seating the rooms"),
          "owner-registration",
          ".steps",
          gettext(
            "The night moves through Registration, Rooms, Debates and Finished. Evening comes: Daria goes to Rooms."
          ),
          as: daria,
          click: ".steps li:nth-child(2) a"
        ),
        step(
          gettext("Seating the rooms"),
          "owner-rooms",
          ".dnd",
          gettext(
            "She drags people into rooms - Anna into Opening Opposition, Petro into the chair - and starts the session."
          ),
          as: daria,
          click: ~s(button[form="allocator-form"])
        ),
        step(
          gettext("The night starts"),
          "me-now",
          "[id^=now-draw-]",
          gettext("Without a reload Anna's My page shows her room, her side and her partner."),
          as: anna
        ),
        step(
          gettext("The motion"),
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
          gettext("The motion"),
          "me-now",
          "#now-motion-box-71",
          gettext(
            "At once the motion is on Anna's page, and 15 minutes of prep count down for the whole room."
          ),
          as: anna
        ),
        step(
          gettext("The ballot"),
          "me-ballot",
          "#now-ballot-71",
          gettext(
            "After the debate Petro fills the ballot: a score for each speaker; the places follow from the team totals."
          ),
          as: petro,
          fill: scores(~w(76 75 75 76 74 73 72 71))
        ),
        step(
          gettext("The ballot"),
          "me-ballot",
          "#now-ballot-71 .bfoot",
          gettext(
            "Two teams on the same total: cab will not take a tie. Petro raises the leader's score, and the ballot is ready."
          ),
          as: petro,
          set: scores(~w(76 75 75 76 74 73 72 71)),
          fill: [{~s(#now-ballot-71 input[name="ballot[oo][LO][score]"]), "77"}],
          click: ~s(button[form="now-ballot-71"])
        ),
        step(
          gettext("Result and feedback"),
          "me-result",
          "#now-result-71",
          gettext(
            "Anna sees the result straight away: her team is first, with its speaker points."
          ),
          as: anna
        ),
        step(
          gettext("Result and feedback"),
          "me-result",
          "#now-feedback-71",
          gettext("Before the night is finished, Anna's team rates the adjudicator."),
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
          gettext("Result and feedback"),
          "me-feedback-sent",
          "#now-feedback-sent-71",
          gettext("Sent. Petro reads it, without the team's name, once the night is over."),
          as: anna
        ),
        step(
          gettext("Finishing"),
          "owner-debates",
          "#session-rooms",
          gettext("Daria follows every room: ballots in, motions out, feedback arriving."),
          as: daria
        ),
        step(
          gettext("Finishing"),
          "owner-debates",
          "#feedback-missing",
          gettext(
            "Two teams have not rated their adjudicator yet. Finishing closes feedback, so Finish asks first."
          ),
          as: daria,
          click: ~s(.seg a[href$="/finish"])
        ),
        step(
          gettext("Finishing"),
          "owner-finished",
          ".seg",
          gettext("The winners are recorded. A wrong ballot? Reopen, fix it and finish again."),
          as: daria,
          click: ".seg a"
        ),
        step(
          gettext("Finishing"),
          "results",
          "[id^=results-card-]",
          gettext(
            "The public results: every room's places and points, ready to paste into the club chat."
          ),
          as: gettext("any visitor")
        ),
        step(
          gettext("After the night"),
          "me-on-me",
          "[id^=feedback-on-me-]",
          gettext(
            "Petro now reads each team's feedback on his call - without the team's name - and his average."
          ),
          as: petro
        ),
        step(
          gettext("After the night"),
          "me-figures",
          "#me-stats",
          gettext(
            "Week after week Anna's My page keeps her figures, straight from the debate engine, and every night she played."
          ),
          as: anna
        ),
        step(
          gettext("No account?"),
          "guest-hub",
          "#now-motion-71",
          gettext(
            "Guests need no account: a personal link opens the same page for their night - the seat, the motion and, for a guest judge, the ballot."
          ),
          as: gettext("Greta, a guest")
        ),
        step(
          gettext("No account?"),
          "owner-form",
          "#guest-form-editor",
          gettext(
            "And between nights Daria keeps the club's own questions: asked once, prefilled after that."
          ),
          as: daria
        ),
        %{
          card(
            gettext("That's the night"),
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
