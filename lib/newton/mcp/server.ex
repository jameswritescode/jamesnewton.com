defmodule Newton.MCP.Server do
  @moduledoc "MCP server exposing read-only post tools, drafts included."

  use Anubis.Server,
    name: "jamesnewton.com",
    version: "1.0.0",
    capabilities: [:tools]

  component(Newton.MCP.Tools.ListPosts)
  component(Newton.MCP.Tools.ReadPost)

  @impl true
  def init(_client_info, frame), do: {:ok, frame}
end
