defmodule NewtonWeb.StandardMetaTest do
  use NewtonWeb.ConnCase, async: true

  alias Newton.Blog
  alias Newton.AccountsFixtures

  @publication "at://did:plc:engjedcb3kwfl4vuo5gtr6n4/site.standard.publication/self"

  defp published_post do
    {:ok, post} =
      Blog.create_post(%{
        slug: "standard-meta-post",
        title: "Standard Meta Post",
        body_markdown: "Body.",
        published_at: DateTime.utc_now()
      })

    post
  end

  test "the well-known endpoint serves the publication AT-URI", %{conn: conn} do
    conn = get(conn, "/.well-known/site.standard.publication")

    assert response_content_type(conn, :text) =~ "text/plain"
    assert response(conn, 200) == @publication
  end

  test "a published post page links its document record", %{conn: conn} do
    post = published_post()
    html = conn |> get(~p"/posts/#{post.slug}") |> html_response(200)

    assert html =~
             ~s(<link rel="site.standard.document" href="at://did:plc:engjedcb3kwfl4vuo5gtr6n4/site.standard.document/standard-meta-post">)

    assert html =~ ~s(<link rel="site.standard.publication" href="#{@publication}">)
  end

  test "preview pages carry no document link", %{conn: conn} do
    {:ok, post} =
      Blog.create_post(%{slug: "standard-draft", title: "Draft", body_markdown: "Shh."})

    {:ok, post} = Blog.enable_preview(post)

    html = conn |> get(~p"/posts/#{post.slug}?p=#{post.preview_token}") |> html_response(200)

    refute html =~ ~s(rel="site.standard.document")
  end

  test "an admin viewing a draft gets no document link", %{conn: conn} do
    {:ok, _} =
      Blog.create_post(%{slug: "admin-draft", title: "Draft", body_markdown: "Shh."})

    html =
      conn
      |> log_in_user(AccountsFixtures.user_fixture())
      |> get(~p"/posts/admin-draft")
      |> html_response(200)

    refute html =~ ~s(rel="site.standard.document")
  end

  test "non-post pages carry no document link", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    refute html =~ ~s(rel="site.standard.document")
    assert html =~ ~s(rel="site.standard.publication")
  end
end
