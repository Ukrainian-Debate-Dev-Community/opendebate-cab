defmodule Public.Tenant.PageTest do
  use ExUnit.Case, async: true

  alias Public.Tenant.Page

  defp parse(body, header \\ "title: About\nnav: 40"),
    do: Page.parse("---\n#{header}\n---\n" <> body)

  test "the header gives the title and the menu place" do
    assert {:ok, %{title: "About", nav: 40, parts: []}} = parse("")
    assert {:ok, %{nav: nil}} = parse("", "title: Rules")
    assert {:error, "the header has no title"} = parse("", "nav: 3")
    assert {:error, "nav is not a number: first"} = parse("", "title: A\nnav: first")
    assert {:error, "no header" <> _} = Page.parse("# About")
  end

  test "blocks and Markdown in their order" do
    body = """
    ::: heading
    The League of Debate
    :::

    ::: cards
    ## Mission
    Debate for all,
    in every city.

    ## Goal
    A club in each town.
    :::

    Some *text* <script>alert(1)</script>

    ::: timeline
    ## 2001
    - 01/05/2001: Founded
    - 09/2001: First cup
    ## 2005
    - 2005: Ten clubs
    :::

    ::: branches :::
    ::: documents :::
    ::: contacts :::
    """

    assert {:ok, %{parts: parts}} = parse(body)

    assert [
             {:heading, "The League of Debate"},
             {:cards,
              [{"Mission", "Debate for all, in every city."}, {"Goal", "A club in each town."}]},
             {:markdown, html},
             {:timeline,
              [
                {"2001", [{"01/05/2001", "Founded"}, {"09/2001", "First cup"}]},
                {"2005", [{"2005", "Ten clubs"}]}
              ]},
             :branches,
             :documents,
             :contacts
           ] = parts

    assert html =~ "<em>text</em>"
    refute html =~ "<script>"
  end

  test "a page that does not read is refused with the reason" do
    assert {:error, "unknown block gallery" <> _} = parse("::: gallery :::")
    assert {:error, "the cards block needs 1 to 3 cards" <> _} = parse("::: cards\nno title\n:::")

    four = Enum.map_join(1..4, "\n", &"## Card #{&1}\ntext")
    assert {:error, "the cards block needs 1 to 3 cards" <> _} = parse("::: cards\n#{four}\n:::")

    assert {:error, "the timeline block needs" <> _} =
             parse("::: timeline\n## 2001\nno dates\n:::")

    assert {:error, "the heading block has no closing :::"} = parse("::: heading\nName")
    assert {:error, "the heading block is empty"} = parse("::: heading\n:::")
  end
end
