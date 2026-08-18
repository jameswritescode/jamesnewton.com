defmodule Newton.MCP.Tools.ListPosts do
  @moduledoc "Lists this site's posts — drafts included — with their publish status."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Newton.Blog

  schema do
    field :status, :enum,
      values: ["all", "draft", "published"],
      default: "all",
      description: "filter by publish status"
  end

  @impl true
  def execute(params, frame) do
    Newton.Telemetry.span(:mcp, :tool_call, %{tool: "list_posts"}, fn ->
      rows =
        params
        |> Map.get(:status, "all")
        |> filter()
        |> Blog.list_posts()
        |> Enum.map(
          &%{slug: &1.slug, title: &1.title, status: status_of(&1), updated_at: &1.updated_at}
        )

      {{:reply, Response.json(Response.tool(), rows), frame}, %{tool: "list_posts", result: :ok}}
    end)
  end

  defp filter("draft"), do: :drafts
  defp filter("published"), do: :published
  defp filter(_), do: :all

  defp status_of(post), do: if(post.published_at, do: "published", else: "draft")
end
