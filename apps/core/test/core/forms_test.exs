defmodule Core.FormsTest do
  @moduledoc """
  Configurable forms: editing a definition (add, edit, remove, move,
  per-field checks, normalise) and checking answers per type.
  """
  use ExUnit.Case, async: true

  alias Core.Forms

  doctest Core.Forms, only: [email?: 1]

  defp add!(definition, params) do
    {:ok, definition} = Forms.add_field(definition, Map.merge(%{"required" => "no"}, params))
    definition
  end

  describe "editing" do
    test "an empty definition asks nothing" do
      assert {:ok, []} = Forms.validate_answers([], %{"x" => "y"})
    end

    test "add, edit, move and remove keep stable ids" do
      form =
        []
        |> add!(%{"label" => " Phone ", "type" => "phone", "required" => "yes"})
        |> add!(%{"label" => "Level", "type" => "choice", "options" => "A\r\nB\n\n C "})

      assert [%{"id" => phone_id} = phone, %{"id" => level_id} = level] = form
      assert phone["label"] == "Phone"
      assert phone["required"] == true
      assert phone["options"] == []
      assert level["options"] == ["A", "B", "C"]
      assert level["required"] == false
      assert phone_id != level_id

      {:ok, form} = Forms.move_field(form, level_id, :up)
      assert Enum.map(form, & &1["id"]) == [level_id, phone_id]
      # at the edge nothing moves
      assert {:ok, ^form} = Forms.move_field(form, level_id, :up)
      assert {:ok, ^form} = Forms.move_field(form, phone_id, :down)

      {:ok, form} =
        Forms.update_field(form, phone_id, %{
          "label" => "Mobile",
          "type" => "phone",
          "required" => "no",
          "hint" => "for the day"
        })

      assert %{"label" => "Mobile", "hint" => "for the day", "required" => false} =
               Forms.field(form, phone_id)

      assert Enum.map(form, & &1["id"]) == [level_id, phone_id]

      {:ok, form} = Forms.remove_field(form, level_id)
      assert [%{"id" => ^phone_id}] = form

      assert {:error, :not_found} = Forms.remove_field(form, "nope")
      assert {:error, :not_found} = Forms.update_field(form, "nope", %{})
      assert {:error, :not_found} = Forms.move_field(form, "nope", :down)
    end

    test "per-field checks" do
      assert {:error, %{label: :required, type: :unknown_type}} =
               Forms.add_field([], %{"label" => " ", "type" => "colour"})

      assert {:error, %{label: {:too_long, 120}}} =
               Forms.add_field([], %{"label" => String.duplicate("x", 121), "type" => "text"})

      assert {:error, %{hint: {:too_long, 200}}} =
               Forms.add_field([], %{
                 "label" => "L",
                 "type" => "text",
                 "hint" => String.duplicate("x", 201)
               })

      assert {:error, %{options: {:options_count, 2, 20}}} =
               Forms.add_field([], %{"label" => "L", "type" => "multi", "options" => "one"})

      many = Enum.map_join(1..21, "\n", &"o#{&1}")

      assert {:error, %{options: {:options_count, 2, 20}}} =
               Forms.add_field([], %{"label" => "L", "type" => "choice", "options" => many})

      assert {:error, %{options: :duplicate_options}} =
               Forms.add_field([], %{"label" => "L", "type" => "choice", "options" => "a\na"})

      assert {:error, %{options: {:option_too_long, 80}}} =
               Forms.add_field([], %{
                 "label" => "L",
                 "type" => "choice",
                 "options" => "a\n" <> String.duplicate("b", 81)
               })

      # options only mean something for the choice types
      assert {:ok, [%{"options" => []}]} =
               Forms.add_field([], %{"label" => "L", "type" => "text", "options" => "x\ny"})

      full = Enum.reduce(1..30, [], fn i, acc -> add!(acc, %{"label" => "F#{i}", "type" => "text"}) end)
      assert {:error, %{form: {:too_many_fields, 30}}} = Forms.add_field(full, %{"label" => "One more", "type" => "text"})
    end

    test "labels, hints and options: invisible text is empty, control characters refused" do
      for blank <- ["\u00A0\u00A0", "\u200B", " \uFEFF\u200D "] do
        assert {:error, %{label: :required}} =
                 Forms.add_field([], %{"label" => blank, "type" => "text"})
      end

      assert {:ok, [%{"label" => "Phone", "hint" => nil}]} =
               Forms.add_field([], %{"label" => "\u200BPhone\u00A0", "hint" => "\u200B ", "type" => "text"})

      assert {:error, %{label: :invalid}} =
               Forms.add_field([], %{"label" => "Ph\u0000one", "type" => "text"})

      assert {:error, %{hint: :invalid}} =
               Forms.add_field([], %{"label" => "L", "hint" => "a\u0007", "type" => "text"})

      assert {:error, %{label: {:too_long, 120}}} =
               Forms.add_field([], %{"label" => " " <> String.duplicate("x", 121), "type" => "text"})

      # an invisible line is no option
      assert {:error, %{options: {:options_count, 2, 20}}} =
               Forms.add_field([], %{"label" => "L", "type" => "choice", "options" => "a\n\u200B\n\u00A0"})

      assert {:ok, [%{"options" => ["a", "b"]}]} =
               Forms.add_field([], %{"label" => "L", "type" => "choice", "options" => "\u200Ba\nb\uFEFF"})

      assert {:error, %{options: :invalid}} =
               Forms.add_field([], %{"label" => "L", "type" => "choice", "options" => "a\nb\u0000"})
    end

    test "every type can be added" do
      for type <- Forms.types() do
        options = if Forms.choice_type?(type), do: "x\ny", else: ""
        assert {:ok, [_]} = Forms.add_field([], %{"label" => type, "type" => type, "options" => options})
      end
    end

    test "normalize checks a stored definition and keeps ids" do
      form = add!([], %{"label" => "A", "type" => "choice", "options" => "x\ny"})
      assert {:ok, ^form} = Forms.normalize(form)

      assert {:ok, [%{"id" => id, "label" => "B", "required" => true}]} =
               Forms.normalize([%{"label" => " B ", "type" => "text", "required" => true}])

      assert is_binary(id) and id != ""

      assert {:error, %{1 => %{type: :unknown_type}}} =
               Forms.normalize([%{"label" => "ok", "type" => "text"}, %{"label" => "bad", "type" => "x"}])

      assert {:error, %{form: :duplicate_id}} = Forms.normalize(form ++ form)
      assert {:error, %{form: :not_a_list}} = Forms.normalize("nope")
    end

    test "field_params turns a field back into editor params" do
      [field] = add!([], %{"label" => "A", "type" => "multi", "options" => "x\ny", "required" => "yes"})

      assert %{"label" => "A", "type" => "multi", "options" => "x\ny", "required" => "yes"} =
               Forms.field_params(field)

      assert %{"type" => "text", "required" => "no"} = Forms.field_params(nil)
    end
  end

  describe "locked fields" do
    @email %{
      "id" => "email",
      "type" => "email",
      "label" => "Your e-mail",
      "hint" => nil,
      "required" => true,
      "options" => []
    }

    setup do
      form =
        Forms.with_locked([], [@email])
        |> add!(%{"label" => "Phone", "type" => "phone"})
        |> add!(%{"label" => "Level", "type" => "choice", "options" => "a\nb"})

      %{form: form}
    end

    test "with_locked puts them first and keeps only their required flag and hint" do
      assert [%{"id" => "email", "locked" => true, "required" => true}] =
               Forms.with_locked([], [@email])

      stored = [
        %{"id" => "x1", "label" => "Phone", "type" => "phone", "required" => false},
        %{"id" => "email", "label" => "Hacked", "type" => "text", "required" => false, "hint" => "h"}
      ]

      assert [email, phone] = Forms.with_locked(stored, [@email])
      assert email == Map.merge(@email, %{"required" => false, "hint" => "h", "locked" => true})
      assert phone["locked"] == false
      assert Forms.with_locked(nil, [@email]) == Forms.with_locked([], [@email])
    end

    test "they cannot be removed or moved, nor can others pass them", %{form: form} do
      [_email, phone, _level] = form
      assert {:error, :locked} = Forms.remove_field(form, "email")
      assert {:error, :locked} = Forms.move_field(form, "email", :down)
      assert {:error, :locked} = Forms.move_field(form, phone["id"], :up)
      assert {:ok, [%{"id" => "email"}, %{"label" => "Level"}, _]} =
               Forms.move_field(form, phone["id"], :down)
    end

    test "an edit changes only required and hint", %{form: form} do
      {:ok, [email | _]} =
        Forms.update_field(form, "email", %{
          "label" => "Other",
          "type" => "text",
          "required" => "no",
          "hint" => "for the link"
        })

      assert email == Map.merge(@email, %{"required" => false, "hint" => "for the link", "locked" => true})

      assert {:error, %{hint: {:too_long, 200}}} =
               Forms.update_field(form, "email", %{"hint" => String.duplicate("x", 201)})
    end

    test "normalize keeps them in place", %{form: [_email, phone, level] = form} do
      sent = [%{"id" => "email", "label" => "X", "type" => "text", "required" => false}, level, phone]
      assert {:ok, [email, ^level, ^phone]} = Forms.normalize(sent, [@email])
      assert email == Map.merge(@email, %{"required" => false, "locked" => true})

      assert {:error, %{form: :locked_removed}} = Forms.normalize([phone], [@email])
      assert {:error, %{form: :locked_moved}} = Forms.normalize([phone, hd(form)], [@email])
      assert {:error, %{form: :locked_removed}} = Forms.normalize([], [@email])
    end

    test "answers treat them like other fields", %{form: form} do
      assert {:error, %{"email" => :required}} = Forms.validate_answers(form, %{})

      assert {:ok, [%{"id" => "email", "label" => "Your e-mail", "value" => "a@b.co"}]} =
               Forms.validate_answers(form, %{"email" => "a@b.co"})
    end
  end

  describe "answers" do
    setup do
      form =
        Enum.reduce(
          [
            %{"label" => "Short", "type" => "text"},
            %{"label" => "Long", "type" => "longtext"},
            %{"label" => "Age", "type" => "number"},
            %{"label" => "Mail", "type" => "email", "required" => "yes"},
            %{"label" => "Phone", "type" => "phone"},
            %{"label" => "Tg", "type" => "telegram"},
            %{"label" => "Rules", "type" => "yesno", "required" => "yes"},
            %{"label" => "Level", "type" => "choice", "options" => "novice\nopen"},
            %{"label" => "Days", "type" => "multi", "options" => "mon\ntue\nwed"}
          ],
          [],
          &add!(&2, &1)
        )

      %{form: form, ids: Map.new(form, &{&1["label"], &1["id"]})}
    end

    defp params(ids, by_label), do: Map.new(by_label, fn {label, v} -> {ids[label], v} end)

    test "valid answers in form order, label and type copied", %{form: form, ids: ids} do
      {:ok, answers} =
        Forms.validate_answers(
          form,
          params(ids, %{
            "Short" => " hi ",
            "Long" => "line one\nline two",
            "Age" => "3,5",
            "Mail" => "a@b.co",
            "Phone" => "+38 (044) 123-45-67",
            "Tg" => "@debater_1",
            "Rules" => "yes",
            "Level" => "open",
            "Days" => ["wed", "mon"]
          })
        )

      assert Enum.map(answers, &{&1["label"], &1["type"], &1["value"]}) == [
               {"Short", "text", "hi"},
               {"Long", "longtext", "line one\nline two"},
               {"Age", "number", "3.5"},
               {"Mail", "email", "a@b.co"},
               {"Phone", "phone", "+38 (044) 123-45-67"},
               {"Tg", "telegram", "debater_1"},
               {"Rules", "yesno", true},
               {"Level", "choice", "open"},
               {"Days", "multi", ["mon", "wed"]}
             ]

      assert Enum.all?(answers, &(&1["id"] == ids[&1["label"]]))
      assert Forms.first_value(answers, "email") == "a@b.co"
      assert Forms.first_value(answers, "url") == nil
    end

    test "required, format and choice checks, one message per field", %{form: form, ids: ids} do
      {:error, errors} =
        Forms.validate_answers(
          form,
          params(ids, %{
            "Age" => "twelve",
            "Phone" => "12-34",
            "Tg" => "@abc",
            "Level" => "expert",
            "Days" => ["mon", "fri"]
          })
        )

      assert errors[ids["Mail"]] == :required
      assert errors[ids["Rules"]] == :required
      assert errors[ids["Age"]] == {:invalid, :number}
      assert errors[ids["Phone"]] == {:invalid, :phone}
      assert errors[ids["Tg"]] == {:invalid, :telegram}
      assert errors[ids["Level"]] == :not_an_option
      assert errors[ids["Days"]] == :not_an_option
      refute Map.has_key?(errors, ids["Short"])
    end

    test "format edges per type", %{form: form, ids: ids} do
      base = %{"Mail" => "a@b.co", "Rules" => "yes"}
      check = fn label, value -> Forms.validate_answers(form, params(ids, Map.put(base, label, value))) end

      assert {:error, %{} = e} = check.("Mail", "a@b")
      assert e[ids["Mail"]] == {:invalid, :email}
      assert {:error, _} = check.("Mail", "a b@c.de")
      assert {:ok, _} = check.("Phone", "1234567")
      assert {:error, _} = check.("Phone", "123456")
      assert {:ok, _} = check.("Phone", String.duplicate("1", 20))
      assert {:error, _} = check.("Phone", String.duplicate("1", 21))
      assert {:error, _} = check.("Phone", "+1 555 CALL ME")
      assert {:error, _} = check.("Phone", "1+234567")
      assert {:ok, _} = check.("Tg", "abcde")
      assert {:ok, _} = check.("Tg", String.duplicate("a", 32))
      assert {:error, _} = check.("Tg", String.duplicate("a", 33))
      assert {:error, _} = check.("Tg", "ab-cde")
      assert {:ok, _} = check.("Age", "-12")
      assert {:ok, _} = check.("Age", "0.25")
      assert {:error, _} = check.("Age", "1e5")
      assert {:error, %{} = e} = check.("Short", String.duplicate("x", 201))
      assert e[ids["Short"]] == {:too_long, 200}
      assert {:error, _} = check.("Long", String.duplicate("x", 2001))
      assert {:error, _} = check.("Level", "Open")
    end

    test "invisible answers are empty; control characters are refused", %{form: form, ids: ids} do
      for blank <- ["   ", "\u00A0", "\u200B\u200C", "\uFEFF"] do
        {:error, errors} = Forms.validate_answers(form, params(ids, %{"Mail" => blank, "Rules" => "yes"}))
        assert errors == %{ids["Mail"] => :required}
      end

      {:ok, answers} =
        Forms.validate_answers(
          form,
          params(ids, %{
            "Mail" => "\u200Ba@b.co\u00A0",
            "Rules" => "yes",
            "Short" => "\u200B",
            "Long" => "one\r\n\ttwo\n"
          })
        )

      assert Enum.map(answers, &{&1["label"], &1["value"]}) == [
               {"Long", "one\n\ttwo"},
               {"Mail", "a@b.co"},
               {"Rules", true}
             ]

      {:error, errors} =
        Forms.validate_answers(
          form,
          params(ids, %{"Mail" => "a@b.co", "Rules" => "yes", "Short" => "a\nb", "Long" => "a\u0000b"})
        )

      assert errors == %{ids["Short"] => :invalid, ids["Long"] => :invalid}

      {:error, errors} =
        Forms.validate_answers(
          form,
          params(ids, %{"Mail" => "a@b.co", "Rules" => "yes", "Short" => "\u00A0" <> String.duplicate("x", 201)})
        )

      assert errors == %{ids["Short"] => {:too_long, 200}}
    end

    test "optional left empty is left out; unticked optional yes/no is a no", %{form: form, ids: ids} do
      form = Enum.map(form, &if(&1["label"] == "Rules", do: Map.put(&1, "required", false), else: &1))

      {:ok, answers} = Forms.validate_answers(form, %{ids["Mail"] => "a@b.co", "nope" => "x"})
      assert Enum.map(answers, &{&1["label"], &1["value"]}) == [{"Mail", "a@b.co"}, {"Rules", false}]
    end

    test "a required choice and multiple choice need a pick", %{form: form, ids: ids} do
      form = Enum.map(form, &Map.put(&1, "required", true))
      {:error, errors} = Forms.validate_answers(form, %{})
      assert errors[ids["Level"]] == :required
      assert errors[ids["Days"]] == :required
    end
  end

  describe "email?/1" do
    test "takes ordinary addresses" do
      for address <- ~w(ada@example.org a.b+tag@mail.example.co.uk o_k-1@x.io a@b.co
                        name@sait.xn--j1amh test@sub.domain.museum) do
        assert Forms.email?(address), address
      end

      assert Forms.email?("ivan@\u043a\u0438\u0457\u0432.\u0443\u043a\u0440")
    end

    test "refuses percent-encoded, control and space characters" do
      for address <- ["a%00b@x.com", "a%40b@x.com", "a\u0000b@x.com", "a\tb@x.com", "a\nb@x.com",
                      "a b@x.com", " a@x.com", "a@x.com\r", "a@x\u00a0.com", "a@x.c\u007fm"] do
        refute Forms.email?(address), inspect(address)
      end
    end

    test "refuses quotes and the characters only a quoted address may hold" do
      for address <- [~s("a"@x.com), "a'b@x.com", "a(b)@x.com", "a,b@x.com", "a:b@x.com",
                      "a;b@x.com", "<a@x.com>", "a[b]@x.com", "a\\b@x.com"] do
        refute Forms.email?(address), inspect(address)
      end
    end

    test "refuses misplaced dots" do
      for address <- ~w(a..b@x.com .a@x.com a.@x.com a@.x.com a@x..com a@x.com.) do
        refute Forms.email?(address), address
      end
    end

    test "refuses a missing or odd top-level domain and a missing part" do
      for address <- ~w(a@x a@x.c a@x.c0m a@x.123 @x.com a@ a a@b@x.com) do
        refute Forms.email?(address), address
      end

      refute Forms.email?("")
      refute Forms.email?(nil)
    end

    test "refuses more than 254 characters" do
      domain = String.duplicate("d", 60) <> ".com"
      ok = String.duplicate("a", 254 - String.length(domain) - 1) <> "@" <> domain
      assert String.length(ok) == 254
      assert Forms.email?(ok)
      refute Forms.email?("a" <> ok)
    end

    test "an e-mail answer uses the same check", %{} do
      form = add!([], %{"label" => "Mail", "type" => "email", "required" => "yes"})
      [%{"id" => id}] = form
      assert {:error, %{^id => {:invalid, :email}}} = Forms.validate_answers(form, %{id => "a%00b@x.com"})
      assert {:ok, [%{"value" => "a@x.com"}]} = Forms.validate_answers(form, %{id => " a@x.com "})
    end
  end

  describe "app attributes" do
    @attrs %{"audience" => {~w(a b c), "c"}}

    test "a field gets the value sent, else the default; others are refused" do
      {:ok, [added]} = Forms.add_field([], %{"label" => "Phone", "type" => "phone"}, @attrs)
      assert added["audience"] == "c"

      {:ok, [chosen]} =
        Forms.add_field([], %{"label" => "Phone", "type" => "phone", "audience" => "a"}, @attrs)

      assert chosen["audience"] == "a"

      assert {:error, %{"audience" => :not_allowed}} =
               Forms.add_field([], %{"label" => "X", "type" => "text", "audience" => "z"}, @attrs)
    end

    test "an edit that sends none keeps the field's" do
      {:ok, [field] = form} =
        Forms.add_field([], %{"label" => "Phone", "type" => "phone", "audience" => "b"}, @attrs)

      {:ok, [kept]} = Forms.update_field(form, field["id"], %{"label" => "Mobile", "type" => "phone"}, @attrs)
      assert kept["audience"] == "b"
      assert Forms.field_params(kept, @attrs)["audience"] == "b"
    end

    test "stored fields without one read the default; core knows no meaning" do
      [stored] = Forms.with_locked([%{"id" => "x", "label" => "Old", "type" => "text"}], [], @attrs)
      assert stored["audience"] == "c"
      assert Forms.attr(%{"audience" => "z"}, "audience", @attrs) == "c"
      assert Forms.field_params(nil, @attrs)["audience"] == "c"

      # no attributes: fields carry none
      {:ok, [plain]} = Forms.add_field([], %{"label" => "Phone", "type" => "phone"})
      refute Map.has_key?(plain, "audience")
    end

    test "normalize checks them like the editor" do
      assert {:error, %{0 => %{"audience" => :not_allowed}}} =
               Forms.normalize([%{"label" => "X", "type" => "text", "audience" => "z"}], [], @attrs)

      assert {:ok, [%{"audience" => "a"}]} =
               Forms.normalize([%{"label" => "X", "type" => "text", "audience" => "a"}], [], @attrs)
    end
  end
end
