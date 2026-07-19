defmodule Newton.StandardTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Newton.Blog.Post
  alias Newton.Standard

  @did "did:plc:engjedcb3kwfl4vuo5gtr6n4"
  @publication "at://#{@did}/site.standard.publication/self"

  @post %Post{
    slug: "hello-world",
    title: "Hello World",
    excerpt: "A first post.",
    published_at: ~U[2026-07-18 12:00:00Z]
  }

  defp enable(overrides \\ []) do
    config = Application.get_env(:newton, Standard)

    Application.put_env(
      :newton,
      Standard,
      config |> Keyword.put(:enabled, true) |> Keyword.merge(overrides)
    )

    on_exit(fn -> Application.put_env(:newton, Standard, config) end)
  end

  defp stub_pds(responder \\ nil) do
    test_pid = self()

    Req.Test.stub(Standard, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:xrpc, conn.request_path, Jason.decode!(body)})

      case responder do
        nil -> Req.Test.json(conn, %{"accessJwt" => "tok", "did" => @did})
        fun -> fun.(conn)
      end
    end)
  end

  setup do
    ref = :telemetry_test.attach_event_handlers(self(), [[:newton, :standard, :sync, :stop]])
    %{ref: ref}
  end

  test "put_document creates a session then puts a metadata-only record keyed by slug", %{
    ref: ref
  } do
    enable()
    stub_pds()

    assert Standard.put_document(@post) == :ok

    assert_received {:xrpc, "/xrpc/com.atproto.server.createSession",
                     %{"identifier" => "jamesnewton.com", "password" => "test-app-password"}}

    assert_received {:xrpc, "/xrpc/com.atproto.repo.putRecord", body}

    assert body == %{
             "repo" => @did,
             "collection" => "site.standard.document",
             "rkey" => "hello-world",
             "record" => %{
               "$type" => "site.standard.document",
               "site" => @publication,
               "title" => "Hello World",
               "path" => "/posts/hello-world",
               "publishedAt" => "2026-07-18T12:00:00Z",
               "description" => "A first post."
             }
           }

    assert_received {[:newton, :standard, :sync, :stop], ^ref, %{duration: _},
                     %{operation: :put_document, result: :ok}}
  end

  test "delete_document removes the slug's record" do
    enable()
    stub_pds()

    assert Standard.delete_document("hello-world") == :ok

    assert_received {:xrpc, "/xrpc/com.atproto.repo.deleteRecord",
                     %{
                       "repo" => @did,
                       "collection" => "site.standard.document",
                       "rkey" => "hello-world"
                     }}
  end

  test "put_publication writes the self record and returns its AT-URI without the enabled gate" do
    stub_pds()

    assert Standard.put_publication() == {:ok, @publication}

    assert_received {:xrpc, "/xrpc/com.atproto.repo.putRecord", body}

    assert body == %{
             "repo" => @did,
             "collection" => "site.standard.publication",
             "rkey" => "self",
             "record" => %{
               "$type" => "site.standard.publication",
               "url" => "https://jamesnewton.com",
               "name" => "James Newton",
               "description" => "Software & Photography",
               "preferences" => %{"showInDiscover" => true}
             }
           }
  end

  test "disabled is a silent no-op for document calls", %{ref: ref} do
    assert Standard.put_document(@post) == :ok
    assert Standard.delete_document("hello-world") == :ok
    refute_received {:xrpc, _, _}
    refute_received {[:newton, :standard, :sync, :stop], ^ref, _, _}
  end

  test "enabled without a publication_uri refuses loudly" do
    enable(publication_uri: nil)

    log =
      capture_log(fn ->
        assert Standard.put_document(@post) == {:error, :publication_not_configured}
      end)

    assert log =~ "publication_uri"
    refute_received {:xrpc, _, _}
  end

  test "a failed session propagates as an error", %{ref: ref} do
    enable()
    stub_pds(fn conn -> Plug.Conn.send_resp(conn, 401, "") end)

    log =
      capture_log(fn ->
        assert {:error, {:session, 401}} = Standard.put_document(@post)
      end)

    assert log =~ "put_document"

    assert_received {[:newton, :standard, :sync, :stop], ^ref, %{duration: _},
                     %{operation: :put_document, result: :error}}
  end

  test "a non-2xx record write propagates as an error" do
    enable()
    test_pid = self()

    Req.Test.stub(Standard, fn conn ->
      {:ok, _body, conn} = Plug.Conn.read_body(conn)

      if String.ends_with?(conn.request_path, "createSession") do
        send(test_pid, :session_ok)
        Req.Test.json(conn, %{"accessJwt" => "tok", "did" => @did})
      else
        Plug.Conn.send_resp(conn, 502, "")
      end
    end)

    log =
      capture_log(fn ->
        assert {:error, {:status, 502}} = Standard.put_document(@post)
      end)

    assert_received :session_ok
    assert log =~ "put_document"
  end

  test "URI helpers derive from config" do
    assert Standard.publication_uri() == @publication
    assert Standard.document_uri("some-slug") == "at://#{@did}/site.standard.document/some-slug"
  end
end
