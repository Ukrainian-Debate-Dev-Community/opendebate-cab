defmodule CabWeb.Tour do
  @moduledoc """
  The guided tours (`/tour/:key`): autoplay walkthroughs of cab for
  newcomers and demos, one per role, each telling one club night in
  order. A tour is data: steps of

    * `chapter`, `text` - the chapter and the caption (shown beside the
      spotlight);
    * `frame` - one of `CabWeb.Tour.Pages`' demo pages (nil: a title
      card), `target` - the CSS selector spotlighted on it (nil: the
      whole page);
    * `set` - `[{selector, value}]` already on the page when the step
      opens (what earlier steps typed); `fill` - what the player types
      (or picks) into the page; `click` - the selector it then clicks;
      the next step shows what the click led to;
    * `as` - whose eyes the page is seen through, when not the tour's
      own `persona`.

  Every step's frame, target, fields and click are checked by the tour
  test, so a page that changes shape fails it - the tours double as a
  consistency check.
  """
  use Gettext, backend: CabWeb.Gettext

  @keys ~w(participant adjudicator head)

  @doc "The tours' keys, in menu order."
  def keys, do: @keys

  @doc "A tour by key, or nil."
  def get(key) when key in @keys, do: tour(key)
  def get(_key), do: nil

  @doc "Every tour."
  def all, do: Enum.map(@keys, &tour/1)

  @doc "The chapters of a tour, in order, each once."
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

  defp tour("participant") do
    %{
      key: "participant",
      title: gettext("The speaker's tour"),
      lead:
        gettext("One club night through a debater's eyes: from finding a club to your figures."),
      persona: gettext("Anna, a speaker"),
      steps: [
        card(
          gettext("Welcome"),
          gettext(
            "Meet Anna. She wants to debate on Thursday nights. Follow her from the first click to her results."
          )
        ),
        step(
          gettext("Find a club"),
          "clubs",
          "#clubs-directory tbody tr",
          gettext("Every club on cab, with its next session. Anna picks Riverside Debate Club."),
          click: "#clubs-directory tbody tr a"
        ),
        step(
          gettext("Find a club"),
          "club-visitor",
          ".chrome .seg",
          gettext("The club's page: who they are and when they meet. Anna asks to join."),
          click: ".chrome .seg a"
        ),
        step(
          gettext("Join"),
          "join",
          "#join-request-form",
          gettext(
            "The club asks one question. Her answer is saved, so she will not type it again."
          ),
          fill: [{~s(#join-request-form input[value="Up to a year"]), "Up to a year"}],
          click: "#join-request-form button[type=submit]"
        ),
        step(
          gettext("Join"),
          "me-pending",
          "#my-clubs tbody tr",
          gettext(
            "On My page the request waits for the club head. Once approved, Anna is a member."
          )
        ),
        step(
          gettext("Register"),
          "me-register",
          "#me-registration",
          gettext(
            "Thursday's session is open. Everything Anna does from now on happens on My page."
          ),
          click: "#open-sessions button[phx-click=open_register]"
        ),
        step(
          gettext("Register"),
          "me-register-form",
          "#me-register-form",
          gettext(
            "The club's question comes prefilled with her saved answer. One click and she is in."
          ),
          click: "#me-register-form button[type=submit]"
        ),
        step(
          gettext("Register"),
          "me-registered",
          "#open-sessions tbody tr",
          gettext("Registered, with Cancel if her plans change. The session is on her schedule.")
        ),
        step(
          gettext("The night"),
          "me-now",
          "[id^=now-draw-]",
          gettext(
            "Thursday evening: the head starts the session. Without a reload Anna sees her room, her side and her partner."
          )
        ),
        step(
          gettext("The night"),
          "me-now",
          "#now-motion-box-71",
          gettext(
            "The adjudicator publishes the motion: it appears here, and 15 minutes of prep count down."
          )
        ),
        step(
          gettext("The result"),
          "me-result",
          "#now-result-71",
          gettext(
            "After the debate the ballot comes in: places and speaker points, straight away."
          )
        ),
        step(
          gettext("Feedback"),
          "me-result",
          "#now-feedback-71",
          gettext("Before the head finishes the night, Anna's team rates the adjudicator."),
          fill: [
            {"#now-feedback-71 input[name=accuracy]", "8"},
            {"#now-feedback-71 input[name=reasoning]", "7"},
            {"#now-feedback-71 textarea[name=discussion]",
             "A clear call, and useful advice on rebuttal."}
          ],
          click: "#now-feedback-71 button[type=submit]"
        ),
        step(
          gettext("Feedback"),
          "me-feedback-sent",
          "#now-feedback-sent-71",
          gettext(
            "Sent. The adjudicator reads it, without the team's name, once the night is over."
          )
        ),
        step(
          gettext("Her figures"),
          "me-figures",
          "#me-stats",
          gettext("Week after week My page keeps her figures, straight from the debate engine.")
        ),
        step(
          gettext("Her figures"),
          "me-figures",
          "#me-history",
          gettext("And every night she played or judged.")
        ),
        step(
          gettext("No account?"),
          "guest-hub",
          "[id^=now-draw-]",
          gettext(
            "A guest registers from the club page without an account and gets a personal link. It opens this same page for that night."
          ),
          as: gettext("Greta, a guest")
        ),
        finale("participant")
      ]
    }
  end

  defp tour("adjudicator") do
    %{
      key: "adjudicator",
      title: gettext("The adjudicator's tour"),
      lead: gettext("One night in the chair: the motion, the ballot and the feedback you get."),
      persona: gettext("Petro, an adjudicator"),
      steps: [
        card(
          gettext("Welcome"),
          gettext(
            "Meet Petro. He registered like everyone else; tonight the head seated him as an adjudicator."
          )
        ),
        step(
          gettext("Your room"),
          "me-chair",
          "[id^=now-draw-]",
          gettext(
            "When the session starts, My page tells Petro the room he chairs and who sits where."
          )
        ),
        step(
          gettext("The motion"),
          "me-chair",
          "#now-motion-71",
          gettext("He types the motion, an infoslide and a keyword, and publishes it."),
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
          "me-ballot",
          "#now-motion-box-71",
          gettext("The room sees the motion at once, and 15 minutes of prep start for everyone.")
        ),
        step(
          gettext("The ballot"),
          "me-ballot",
          "#now-ballot-71",
          gettext(
            "After the debate, the ballot: a score for each speaker. The places follow from the team totals."
          ),
          fill: scores(~w(76 75 75 76 74 73 72 71))
        ),
        step(
          gettext("The ballot"),
          "me-ballot",
          "#now-ballot-71 .bfoot",
          gettext(
            "Two teams on the same total: cab will not take a tie. Petro raises the leader's score, and the ballot is ready."
          ),
          set: scores(~w(76 75 75 76 74 73 72 71)),
          fill: [{~s(#now-ballot-71 input[name="ballot[oo][LO][score]"]), "77"}],
          click: ~s(button[form="now-ballot-71"])
        ),
        step(
          gettext("The ballot"),
          "me-ballot-in",
          "#now-result-71",
          gettext(
            "Submitted: the room sees the result. From now on only the club head can change it."
          )
        ),
        step(
          gettext("Feedback on you"),
          "me-on-me",
          "[id^=feedback-on-me-]",
          gettext(
            "Once the night is finished, Petro reads each team's feedback - without the team's name - and his average."
          )
        ),
        step(
          gettext("Feedback on you"),
          "me-on-me",
          "#me-history",
          gettext("Every night he judged stays in his history.")
        ),
        step(
          gettext("No account?"),
          "guest-hub",
          "#now-motion-71",
          gettext(
            "A guest adjudicator gets the same on their personal link page: the motion form and the ballot."
          ),
          as: gettext("Greta, a guest")
        ),
        finale("adjudicator")
      ]
    }
  end

  defp tour("head") do
    %{
      key: "head",
      title: gettext("The club head's tour"),
      lead: gettext("Running one club night, from opening the session to the results."),
      persona: gettext("Daria, the club head"),
      steps: [
        card(
          gettext("Welcome"),
          gettext(
            "Meet Daria. She runs Riverside Debate Club, and tonight is Thursday night. Let's run it."
          )
        ),
        step(
          gettext("Open the night"),
          "owner-club",
          "#open-session-form",
          gettext(
            "A name, the date, the format and a place limit, and the session takes sign-ups."
          ),
          fill: [{"#open-session-form input[name=name]", "Thursday night"}],
          click: ~s(button[form="open-session-form"])
        ),
        step(
          gettext("Registration"),
          "owner-registration",
          "#shared-registration-url",
          gettext(
            "Daria shares one link. Members register on My page, guests from the club page."
          )
        ),
        step(
          gettext("Registration"),
          "owner-registration",
          "#session-people",
          gettext(
            "Sign-ups arrive live. She can add people by hand; a guest gets a personal link of their own."
          )
        ),
        step(
          gettext("Registration"),
          "owner-registration",
          ".steps",
          gettext(
            "The night moves through Registration, Rooms, Debates and Finished. Daria goes to Rooms."
          ),
          click: ".steps li:nth-child(2) a"
        ),
        step(
          gettext("Rooms"),
          "owner-rooms",
          ".dnd",
          gettext(
            "She drags people into rooms and seats an adjudicator in each; nobody is placed automatically. Then she starts the session."
          ),
          click: ~s(button[form="allocator-form"])
        ),
        step(
          gettext("Debates"),
          "owner-debates",
          "#session-rooms",
          gettext(
            "The session runs. Motions and ballots arrive as the adjudicators work on their own My page."
          )
        ),
        step(
          gettext("Debates"),
          "owner-debates",
          "#feedback-missing",
          gettext(
            "Before finishing she sees which teams have not rated their adjudicator yet: finishing closes feedback."
          ),
          click: ~s(.seg a[href$="/finish"])
        ),
        step(
          gettext("Finished"),
          "owner-finished",
          ".seg",
          gettext("The winners are recorded. A wrong ballot? Reopen, fix it and finish again."),
          click: ".seg a"
        ),
        step(
          gettext("Results"),
          "results",
          "[id^=results-card-]",
          gettext(
            "The public results: every room's places and points, ready to paste into the club chat."
          ),
          as: gettext("any visitor")
        ),
        step(
          gettext("Between nights"),
          "owner-members",
          "#join-requests",
          gettext(
            "Between nights, join requests arrive with their answers. Daria approves them."
          ),
          click: ~s(#join-requests a[href$="/approve"])
        ),
        step(
          gettext("Between nights"),
          "owner-form",
          "#guest-form-editor",
          gettext(
            "Her own registration questions: members answer once, and the answers come prefilled after that."
          )
        ),
        step(
          gettext("Between nights"),
          "owner-club",
          "#club-profile-form",
          gettext("And the club's profile: what visitors see on its page.")
        ),
        finale("head")
      ]
    }
  end

  defp finale(key) do
    others = Enum.reject(@keys, &(&1 == key))

    %{
      card(
        gettext("That's the night"),
        gettext("Thanks for watching. Find a club to try it, or watch %{tours}.",
          tours: Enum.map_join(others, gettext(" or "), &tour_title/1)
        )
      )
      | finale: true
    }
  end

  defp tour_title("participant"), do: gettext("the speaker's tour")
  defp tour_title("adjudicator"), do: gettext("the adjudicator's tour")
  defp tour_title("head"), do: gettext("the club head's tour")

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
