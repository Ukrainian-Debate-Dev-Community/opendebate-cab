defmodule Cab.DevSeeds do
  @moduledoc """
  DEV ONLY seeding helpers behind the left debug panel (rendered only
  when :dev_routes is enabled). Generates bot
  participants so flows can be exercised without hand-registering a
  cast. Bots are real gateway users with real engine counterparts —
  everything runs through the same code paths as live users.
  """

  alias Cab.{Accounts, Clubs, EngineApi, Repo, Tournaments}
  alias Cab.Accounts.User

  @team_words ~w(Aurora Borax Cinder Drift Ember Flint Gale Harbor Iris Juniper Krait Lumen)
  @first_names ~w(Ada Bram Cleo Dara Edna Fia Gus Hale Ida Jara Kip Lena Mio Nia Otto Pia)

  @doc """
  Seeds a tournament with `team_count` bot teams (2 shadow speakers
  each) and `judge_count` bot judges, acting as `actor` (who must be
  an organiser of the event).
  """
  def seed_tournament(actor, event_id, team_count, judge_count)
      when team_count in 1..64 and judge_count in 0..16 do
    suffix = suffix()

    lines =
      Enum.map_join(1..team_count, "\n", fn i ->
        word = Enum.at(@team_words, rem(i - 1, length(@team_words)))
        a = Enum.at(@first_names, rem(2 * i, length(@first_names)))
        b = Enum.at(@first_names, rem(2 * i + 1, length(@first_names)))
        "#{word} #{suffix}-#{i}: #{a} #{suffix}#{i}A, #{b} #{suffix}#{i}B"
      end)

    with {:ok, teams} <- Tournaments.create_teams_from_lines(actor, event_id, lines),
         {:ok, judges} <- seed_judges(actor, event_id, judge_count, suffix) do
      {:ok, %{teams: teams, judges: judges}}
    end
  end

  defp seed_judges(_actor, _event_id, 0, _suffix), do: {:ok, 0}

  defp seed_judges(actor, event_id, count, suffix) do
    Enum.reduce_while(1..count, {:ok, 0}, fn i, {:ok, done} ->
      case EngineApi.provision_participant(
             actor,
             event_id,
             "Judge #{Enum.at(@first_names, rem(i, length(@first_names)))} #{suffix}",
             "adjudicator"
           ) do
        {:ok, _} -> {:cont, {:ok, done + 1}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  @doc """
  Fills the club's OPEN session with bot sign-ups: `speaker_count`
  bots register themselves to speak and `judge_count` to judge — the
  exact registration path real members use.
  """
  def seed_club_signups(club_id, speaker_count, judge_count)
      when speaker_count in 0..64 and judge_count in 0..16 do
    suffix = suffix()

    with %{engine_organisation_id: org_id} = club when not is_nil(org_id) <-
           Clubs.get_club(club_id),
         {:ok, reader} <- bot_user("bot-reader"),
         {:ok, session} <- Clubs.current_session(reader.node_user_id, org_id),
         {:ok, %{event: event}} <- signup_stage(session) do
      with {:ok, speakers} <- signup_bots(event["id"], "speaker", speaker_count, suffix),
           {:ok, judges} <- signup_bots(event["id"], "adjudicator", judge_count, suffix) do
        {:ok, %{speakers: speakers, judges: judges, club: club.name}}
      end
    else
      nil -> {:error, "club not found"}
      %Cab.Clubs.Club{} -> {:error, "club has no engine organisation yet — open a session first"}
      {:error, message} -> {:error, message}
    end
  end

  defp signup_stage(nil), do: {:error, "no open session for this club — open one on /club first"}
  defp signup_stage(%{stage: :signup} = session), do: {:ok, session}
  defp signup_stage(%{stage: stage}), do: {:error, "session is past sign-up (#{stage})"}

  defp signup_bots(_event_id, _role, 0, _suffix), do: {:ok, 0}

  defp signup_bots(event_id, role, count, suffix) do
    prefix = if role == "adjudicator", do: "judge", else: "bot"

    Enum.reduce_while(1..count, {:ok, 0}, fn i, {:ok, done} ->
      name = Enum.at(@first_names, rem(i * 3, length(@first_names))) |> String.downcase()

      with {:ok, bot} <- bot_user("#{prefix}-#{name}-#{suffix}#{i}"),
           {:ok, _} <- Clubs.signup(bot.node_user_id, event_id, bot.username, role) do
        {:cont, {:ok, done + 1}}
      else
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  @doc """
  Gets or creates a gateway bot user with an engine counterpart.
  """
  def bot_user(username) do
    user =
      Repo.get_by(User, username: username) ||
        Repo.insert!(User.changeset(%User{}, %{username: username}))

    case Accounts.ensure_node_user(user) do
      %{node_user_id: nil} ->
        {:error, "could not provision engine user for #{username} — is the engine running?"}

      user ->
        {:ok, user}
    end
  end

  defp suffix, do: :crypto.strong_rand_bytes(2) |> Base.encode16(case: :lower)
end
