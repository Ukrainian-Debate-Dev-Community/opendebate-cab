defmodule CabWeb.Tour do
  @moduledoc """
  The guided tours (`/tour/:key`): autoplay walkthroughs of cab for
  newcomers and demos, one per role. A tour is data - steps of
  `%{chapter, frame, target, text, seconds}`: the frame is one of
  `CabWeb.Tour.Pages`' demo pages (nil: a title card), the target a CSS
  selector spotlighted on it (nil: the whole page). Every step's frame
  and target are checked by the tour test, so a page that changes
  shape fails it - the tours double as a consistency check.
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

  defp tour("participant") do
    %{
      key: "participant",
      title: gettext("The speaker's tour"),
      lead: gettext("From finding a club to your figures: everything a debater does in cab."),
      steps:
        [intro()] ++
          [
            step(
              gettext("Find a club"),
              "clubs",
              "#clubs-directory",
              7,
              gettext("Every club on cab, each with its next session. Pick one to see its page.")
            ),
            step(
              gettext("Find a club"),
              "club",
              "#register",
              8,
              gettext(
                "A club's page: who they are, when they meet, and the next session open for sign-up."
              )
            ),
            step(
              gettext("Join"),
              "join",
              "#join-request-form",
              8,
              gettext("Ask to join: answer the club's questions once; the head approves you.")
            ),
            step(
              gettext("My page"),
              "me-register",
              nil,
              7,
              gettext(
                "My page is your one place: registration, your seat, the motion, feedback and your figures."
              )
            ),
            step(
              gettext("Register"),
              "me-register",
              "#me-registration",
              8,
              gettext(
                "Sessions open in your clubs show here, with the places left. Register or cancel in one click."
              )
            ),
            step(
              gettext("Register"),
              "club",
              "#register-form",
              8,
              gettext(
                "The club's questions come prefilled with your saved answers, so registering takes seconds."
              )
            ),
            step(
              gettext("Your schedule"),
              "me-schedule",
              "#my-schedule",
              6,
              gettext("Once registered, the session is on your schedule.")
            ),
            step(
              gettext("The session starts"),
              "me-now",
              "[id^=now-]",
              9,
              gettext(
                "When the head starts the session, Now shows your room, your side and role, and your team - live, no reload."
              )
            ),
            step(
              gettext("Motion and prep"),
              "me-now",
              "#prep-71",
              8,
              gettext(
                "The motion appears the moment the adjudicator publishes it, and the prep clock counts down."
              )
            ),
            step(
              gettext("The result"),
              "me-result",
              "#now-feedback-71",
              9,
              gettext(
                "Once the ballot is in you see the places and points - and your team gives feedback on the adjudicator, before the head finishes."
              )
            ),
            step(
              gettext("Your figures"),
              "me-figures",
              "#me-stats",
              8,
              gettext("Your figures come straight from the debate engine, one format at a time.")
            ),
            step(
              gettext("Your figures"),
              "me-figures",
              "#me-history",
              6,
              gettext("And every session you played or judged.")
            ),
            step(
              gettext("Coming as a guest"),
              "guest-hub",
              nil,
              9,
              gettext(
                "No account? Register as a guest: your personal link opens the same page for that session - seat, motion, ballot and feedback."
              )
            )
          ] ++ [outro("participant")]
    }
  end

  defp tour("adjudicator") do
    %{
      key: "adjudicator",
      title: gettext("The adjudicator's tour"),
      lead: gettext("Publishing the motion, filling the ballot, and the feedback you get."),
      steps:
        [intro()] ++
          [
            step(
              gettext("Register as usual"),
              "me-register",
              "#me-registration",
              7,
              gettext(
                "Judges register like everyone else: the head's seating decides who adjudicates."
              )
            ),
            step(
              gettext("You chair a room"),
              "me-chair",
              "[id^=now-]",
              8,
              gettext("Now tells you which room you adjudicate, with the teams in their seats.")
            ),
            step(
              gettext("Publish the motion"),
              "me-chair",
              "#now-motion-71",
              9,
              gettext(
                "Type the motion, an infoslide and a keyword. Publishing shows it to the room and starts 15 minutes of prep."
              )
            ),
            step(
              gettext("Fill the ballot"),
              "me-ballot",
              "#now-ballot-71",
              9,
              gettext(
                "Pick each speaker and score them from 50 to 100; the places follow from the team totals."
              )
            ),
            step(
              gettext("The tie gate"),
              "me-tie",
              "#now-ballot-71",
              8,
              gettext(
                "Two teams on the same total are refused, and what you typed stays on the form."
              )
            ),
            step(
              gettext("After you submit"),
              "me-ballot-in",
              "[id^=now-]",
              8,
              gettext(
                "The ballot is in: the room sees the result. From now on only the club head can change it."
              )
            ),
            step(
              gettext("Feedback on you"),
              "me-on-me",
              "[id^=feedback-on-me-]",
              9,
              gettext(
                "Once the session is finished you see each team's feedback - without the team's name - and your average."
              )
            ),
            step(
              gettext("Your record"),
              "me-on-me",
              "#me-history",
              6,
              gettext("Every session you judged stays in your history.")
            ),
            step(
              gettext("Judging as a guest"),
              "guest-hub",
              "[id^=now-]",
              8,
              gettext(
                "A guest judge gets the same on their personal link page: the motion form and the ballot."
              )
            )
          ] ++ [outro("adjudicator")]
    }
  end

  defp tour("head") do
    %{
      key: "head",
      title: gettext("The club head's tour"),
      lead: gettext("Running a club night from the first sign-up to the results."),
      steps:
        [intro()] ++
          [
            step(
              gettext("Your club"),
              "owner-club",
              "#club-profile-form",
              8,
              gettext("Your club's profile, edited in place: what visitors see on its page.")
            ),
            step(
              gettext("Members"),
              "owner-members",
              "#join-requests",
              8,
              gettext("Join requests arrive with their answers: approve or decline.")
            ),
            step(
              gettext("Members"),
              "owner-members",
              "#members-list",
              6,
              gettext("Your members, each removable.")
            ),
            step(
              gettext("The registration form"),
              "owner-form",
              "#guest-form-editor",
              8,
              gettext(
                "Your own questions: members answer them once and get them prefilled after that."
              )
            ),
            step(
              gettext("Open a session"),
              "owner-club",
              "#open-session-form",
              8,
              gettext("Name, date, format and a place limit - and the session takes sign-ups.")
            ),
            step(
              gettext("The stages"),
              "owner-registration",
              ".steps",
              8,
              gettext(
                "A session moves through Registration, Rooms, Debates and Finished; you can switch between them freely."
              )
            ),
            step(
              gettext("Sessions"),
              "owner-registration",
              "#session-picker",
              6,
              gettext("Every session of your club is one pick away.")
            ),
            step(
              gettext("Registration"),
              "owner-registration",
              "#shared-registration-url",
              7,
              gettext("Share one link: members and guests register from the club page.")
            ),
            step(
              gettext("Registration"),
              "owner-registration",
              "#session-people",
              8,
              gettext(
                "Sign-ups arrive live. Add people by hand; guests get a personal link of their own."
              )
            ),
            step(
              gettext("Rooms"),
              "owner-rooms",
              ".dnd",
              9,
              gettext(
                "Drag people into rooms: nobody is placed automatically. Start session opens the rooms."
              )
            ),
            step(
              gettext("Debates"),
              "owner-debates",
              "#session-rooms",
              8,
              gettext(
                "Each room's motion and ballot arrive as the adjudicators work on their My page."
              )
            ),
            step(
              gettext("Before Finish"),
              "owner-debates",
              "#feedback-missing",
              8,
              gettext("Who has not sent feedback yet: finishing closes it, so Finish asks first.")
            ),
            step(
              gettext("Feedback"),
              "owner-debates",
              "#session-feedback",
              7,
              gettext("You read every team's feedback, with the team.")
            ),
            step(
              gettext("Finish and reopen"),
              "owner-finished",
              nil,
              7,
              gettext("Finish records the winners. Reopen to fix a ballot and finish again.")
            ),
            step(
              gettext("Results"),
              "results",
              "[id^=results-card-]",
              8,
              gettext("The results page, public: every room's places and points, ready to share.")
            )
          ] ++ [outro("head")]
    }
  end

  defp intro do
    step(
      gettext("Welcome"),
      nil,
      nil,
      6,
      gettext(
        "cab runs a debate club's nights: every role works in one place. Sit back - this tour plays by itself."
      )
    )
  end

  defp outro(key) do
    others = Enum.reject(@keys, &(&1 == key))

    step(
      gettext("That's it"),
      nil,
      nil,
      6,
      gettext("Thanks for watching. The other tours: %{tours}.",
        tours: Enum.map_join(others, ", ", &tour_title/1)
      )
    )
  end

  defp tour_title("participant"), do: gettext("the speaker's")
  defp tour_title("adjudicator"), do: gettext("the adjudicator's")
  defp tour_title("head"), do: gettext("the club head's")

  defp step(chapter, frame, target, seconds, text),
    do: %{chapter: chapter, frame: frame, target: target, seconds: seconds, text: text}
end
