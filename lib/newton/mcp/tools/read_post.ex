defmodule Newton.MCP.Tools.ReadPost do
  @moduledoc "Reads one post by slug — the markdown source, drafts included."

  use Anubis.Server.Component,
    type: :tool,
    annotations: %{"readOnlyHint" => true, "idempotentHint" => true, "openWorldHint" => false}

  alias Anubis.Server.Response
  alias Newton.Blog

  schema do
    field :slug, :string, required: true, description: "the post's slug"
  end

  @impl true
  def execute(%{slug: slug}, frame) do
    Newton.Telemetry.span(:mcp, :tool_call, %{tool: "read_post"}, fn ->
      case Blog.get_post_by_slug(slug) do
        nil ->
          reply =
            Response.error(
              Response.tool(),
              "no post with slug #{inspect(slug)} — call list_posts to see available slugs"
            )

          {{:reply, reply, frame}, %{tool: "read_post", result: :not_found}}

        post ->
          payload = %{
            slug: post.slug,
            title: post.title,
            status: if(post.published_at, do: "published", else: "draft"),
            excerpt: post.excerpt,
            body_markdown: post.body_markdown
          }

          {{:reply, Response.json(Response.tool(), payload), frame},
           %{tool: "read_post", result: :ok}}
      end
    end)
  end
end
