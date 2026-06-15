defmodule NewtonWeb.ContentSecurityPolicy do
  @moduledoc """
  Sets a per-request Content-Security-Policy. Inline `<script>` tags are allowed
  only via a fresh per-request nonce (assigned as `@csp_nonce`), so `script-src`
  stays strict — no `'unsafe-inline'`. Styles use `'unsafe-inline'` because the
  app emits inline `style=` attributes (progress bars, the loading bar, etc.);
  Google Fonts hosts are allowlisted for CSS and font files.
  """
  @behaviour Plug
  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    nonce = 18 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header("content-security-policy", policy(nonce))
  end

  defp policy(nonce) do
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
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
        "script-src 'self' 'nonce-#{nonce}'",
        "connect-src 'self'"
      ],
      "; "
    )
  end
end
