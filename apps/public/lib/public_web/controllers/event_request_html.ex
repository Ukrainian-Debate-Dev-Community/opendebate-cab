defmodule PublicWeb.EventRequestHTML do
  use PublicWeb, :html

  import CabWeb.FormComponents,
    only: [
      answer_name: 1,
      block_type: 1,
      field_label: 1,
      input_type: 1,
      placeholder: 1,
      prompt: 1
    ]

  embed_templates "event_request_html/*"
end
