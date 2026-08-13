defmodule NewtonWeb.ContentSecurityPolicy do
  @moduledoc """
  Sets a per-request Content-Security-Policy. Inline `<script>` tags are allowed
  only via a fresh per-request nonce (assigned as `@csp_nonce`), so `script-src`
  stays strict — no `'unsafe-inline'`. Google Fonts hosts are allowlisted for
  CSS and font files.

  `style-src` is strict by default. Pass `style_src: :allow_inline` on the
  routes that need it — CSP nonces cover `<style>` elements but cannot be
  applied to a `style=` attribute, and the admin renders bar widths that way.
  Public pages carry no inline styles, so they get the strict policy: a future
  HTML-injection bug there cannot reach for CSS exfiltration or defacement.
  """
  @behaviour Plug
  import Plug.Conn

  @impl true
  def init(opts), do: Keyword.get(opts, :style_src, :strict)

  @impl true
  def call(conn, style_src) do
    nonce = 18 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header("content-security-policy", policy(nonce, style_src))
  end

  defp policy(nonce, style_src) do
    Enum.join(
      [
        "default-src 'self'",
        "base-uri 'self'",
        "frame-ancestors 'none'",
        "object-src 'none'",
        "form-action 'self'",
        # Photos may be uploaded (self/`/media`) or referenced by absolute URL
        # (`Gallery.image_url/1` passes those through); `blob:` is the upload
        # dimension-reader.
        "img-src 'self' data: blob: https:",
        "font-src 'self' https://fonts.gstatic.com",
        style_src(style_src),
        "script-src 'self' 'nonce-#{nonce}'",
        "connect-src 'self'"
      ],
      "; "
    )
  end

  defp style_src(:allow_inline),
    do: "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com"

  defp style_src(:strict), do: "style-src 'self' https://fonts.googleapis.com"
end
