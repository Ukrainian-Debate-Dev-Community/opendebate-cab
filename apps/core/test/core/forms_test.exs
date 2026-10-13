defmodule Core.FormsTest do
  @moduledoc """
  Configurable forms: editing a definition (add, edit, remove, move,
  per-field checks, normalise) and checking answers per type.
  """
  use ExUnit.Case, async: true

  alias Core.Forms

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
end
