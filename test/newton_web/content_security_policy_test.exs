defmodule NewtonWeb.ContentSecurityPolicyTest do
  use NewtonWeb.ConnCase, async: true

  test "browser responses carry a CSP that restricts scripts to self + a nonce", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "default-src 'self'"
    assert csp =~ "frame-ancestors 'none'"
    assert csp =~ "object-src 'none'"
    assert csp =~ ~r/script-src 'self' 'nonce-[A-Za-z0-9_-]+'/
    refute csp =~ "script-src 'self' 'unsafe-inline'"
  end

  test "the inline setup script carries the matching CSP nonce", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    [csp] = get_resp_header(conn, "content-security-policy")
    [_, nonce] = Regex.run(~r/'nonce-([A-Za-z0-9_-]+)'/, csp)

    assert html =~ ~s(<script nonce="#{nonce}">)
  end
end
