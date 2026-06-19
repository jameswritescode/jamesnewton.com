defmodule NewtonWeb.ErrorHTML do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  See config/config.exs.
  """
  use NewtonWeb, :html

  embed_templates "error_html/*"

  # Fallback for statuses without a dedicated template (e.g. 500): render the
  # plain status text ("Internal Server Error") inside the root layout.
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
