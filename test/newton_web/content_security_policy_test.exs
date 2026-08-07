defmodule NewtonWeb.ContentSecurityPolicyTest do
  use NewtonWeb.ConnCase, async: true

  import Newton.AccountsFixtures

  test "browser responses carry a CSP that restricts scripts to self + a nonce", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "default-src 'self'"
    assert csp =~ "frame-ancestors 'none'"
    assert csp =~ "object-src 'none'"
    assert csp =~ ~r/script-src 'self' 'nonce-[A-Za-z0-9_-]+'/
    refute csp =~ "script-src 'self' 'unsafe-inline'"
  end

  # The public site is dark-only with no inline scripts, so the nonce'd inline
  # setup script now lives only in the admin layout (its theme toggle).
  test "the admin inline setup script carries the matching CSP nonce", %{conn: conn} do
    conn = conn |> log_in_user(user_fixture()) |> get(~p"/admin")
    html = html_response(conn, 200)

    [csp] = get_resp_header(conn, "content-security-policy")
    [_, nonce] = Regex.run(~r/'nonce-([A-Za-z0-9_-]+)'/, csp)

    assert html =~ ~s(<script nonce="#{nonce}">)
  end

  describe "machine-readable routes" do
    for path <- ["/sitemap.xml", "/robots.txt", "/.well-known/site.standard.publication"] do
      test "#{path} carries security headers despite skipping :browser", %{conn: conn} do
        conn = get(conn, unquote(path))

        assert conn.status == 200
        assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
        assert [csp] = get_resp_header(conn, "content-security-policy")
        assert csp =~ "frame-ancestors 'none'"
      end
    end

    test "an unknown OG slug renders the error page with a usable nonce", %{conn: conn} do
      # The miss returns HTML through the root layout. Once a CSP is in force the
      # layout's inline script must be nonce'd, or it is blocked on this page only.
      {404, headers, html} =
        assert_error_sent(404, fn -> get(conn, ~p"/og/posts/no-such-post") end)

      assert {_, csp} = List.keyfind(headers, "content-security-policy", 0)
      assert [_, nonce] = Regex.run(~r/'nonce-([A-Za-z0-9_-]+)'/, csp)

      for tag <- Regex.scan(~r/<script(?![^>]*\ssrc=)[^>]*>/, html) do
        assert hd(tag) =~ ~s(nonce="#{nonce}"), "inline script without the CSP nonce: #{hd(tag)}"
      end
    end
  end
end
