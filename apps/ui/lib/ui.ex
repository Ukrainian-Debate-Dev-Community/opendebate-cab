defmodule Ui do
  @moduledoc """
  The component library of the web apps: `use Ui` imports the kit
  (`Ui.Components`: table, section, banner, stepper, ...) and the form
  (`Ui.Form`: `form_for` and its blocks). `Ui.FormComponents` (the UI
  of `Core.Forms`) is called by name or imported with `only:`.

  ui knows no app: links, records and an app's own words come in as
  attrs and slots from the caller. Its texts go through `Ui.Gettext`.
  """

  defmacro __using__(_opts) do
    quote do
      import Ui.Components
      import Ui.Form
    end
  end
end
