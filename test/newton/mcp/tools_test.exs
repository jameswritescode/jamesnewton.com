defmodule Newton.MCP.ToolsTest do
  use Newton.DataCase, async: true

  alias Anubis.Server.{Frame, Response}
  alias Newton.MCP.Tools.{ListPosts, ReadPost}

  defp create_draft!(title, body) do
    {:ok, post} =
      Newton.Blog.create_post(%{
        title: title,
        slug: Newton.Slug.slugify(title),
        body_markdown: body
      })

    post
  end

  defp decoded_json(%Response{content: [%{"type" => "text", "text" => text}]}) do
    Jason.decode!(text)
  end

  describe "list_posts" do
    test "includes drafts with status all" do
      post = create_draft!("My draft", "body")

      assert {:reply, %Response{isError: false} = response, %Frame{}} =
               ListPosts.execute(%{status: "all"}, %Frame{})

      rows = decoded_json(response)
      assert Enum.any?(rows, &(&1["slug"] == post.slug and &1["status"] == "draft"))
      assert Enum.all?(rows, &(Map.keys(&1) |> Enum.sort() == ~w(slug status title updated_at)))
    end

    test "status filter narrows to drafts" do
      create_draft!("Draft only", "body")

      assert {:reply, response, _} = ListPosts.execute(%{status: "published"}, %Frame{})
      assert decoded_json(response) |> Enum.filter(&(&1["status"] == "draft")) == []

      assert {:reply, response, _} = ListPosts.execute(%{status: "draft"}, %Frame{})
      assert decoded_json(response) |> Enum.all?(&(&1["status"] == "draft"))
    end

    test "schema exposes the status enum with default all" do
      schema = ListPosts.input_schema()
      assert schema["properties"]["status"]["enum"] == ["all", "draft", "published"]
    end
  end

  describe "read_post" do
    test "returns a draft's markdown body" do
      post = create_draft!("Readable draft", "# Heading\n\nSecret draft body")

      assert {:reply, %Response{isError: false} = response, %Frame{}} =
               ReadPost.execute(%{slug: post.slug}, %Frame{})

      body = decoded_json(response)
      assert body["title"] == "Readable draft"
      assert body["status"] == "draft"
      assert body["body_markdown"] =~ "Secret draft body"
    end

    test "unknown slug returns a tool error, not a raise" do
      assert {:reply, %Response{isError: true} = response, %Frame{}} =
               ReadPost.execute(%{slug: "missing"}, %Frame{})

      assert [%{"type" => "text", "text" => text}] = response.content
      assert text =~ "no post with slug"
    end

    test "tool calls emit the telemetry stop event" do
      :telemetry_test.attach_event_handlers(self(), [[:newton, :mcp, :tool_call, :stop]])
      create_draft!("Telemetered", "body")

      ListPosts.execute(%{status: "all"}, %Frame{})

      assert_receive {[:newton, :mcp, :tool_call, :stop], _ref, _measurements, metadata}
      assert metadata.tool == "list_posts"
      assert metadata.result == :ok
      assert Map.keys(metadata) |> Enum.sort() == [:result, :telemetry_span_context, :tool]
    end
  end
end
