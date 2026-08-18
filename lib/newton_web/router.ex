defmodule NewtonWeb.Router do
  use NewtonWeb, :router

  import NewtonWeb.UserAuth

  pipeline :browser do
    # json is accepted for same-origin XHR endpoints in this scope (the passkey
    # login challenge/verify); normal navigations still negotiate to html.
    plug :accepts, ["html", "json"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {NewtonWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug NewtonWeb.ContentSecurityPolicy
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # The admin renders bar widths as `style=` attributes, which no nonce can
  # cover. Re-running the plug after :browser replaces the strict header (and
  # its nonce assign) with one that permits them, keeping the relaxation behind
  # authentication instead of applying it site-wide.
  pipeline :admin_csp do
    plug NewtonWeb.ContentSecurityPolicy, style_src: :allow_inline
  end

  # Headers for machine-facing routes that skip :browser (no session, no CSRF).
  # The CSP plug is here for its `@csp_nonce` assign as much as its header: these
  # routes render the HTML error page on a miss, and the root layout's inline
  # script needs a nonce once a policy is in force.
  pipeline :machine_readable do
    plug :put_secure_browser_headers
    plug NewtonWeb.ContentSecurityPolicy
  end

  scope "/", NewtonWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/resume", PageController, :resume
    get "/posts", PostController, :index
    get "/posts/:slug", PostController, :show
    get "/blog", PageController, :blog_redirect
    get "/blog/:slug", PageController, :blog_redirect
    get "/reading", ReadingController, :index
    get "/photos", PhotoController, :index
    get "/links", LinksController, :index
  end

  # Social card images. Skips :browser (no session/CSRF) but still carries
  # security headers, because an unknown slug renders the HTML error page.
  scope "/og", NewtonWeb do
    pipe_through :machine_readable

    get "/posts/:slug", OgImageController, :show
  end

  # Crawler endpoints. Skips :browser (no session/CSRF); the controller sets
  # content-type + caching, the pipeline sets the security headers.
  scope "/", NewtonWeb do
    pipe_through :machine_readable

    get "/sitemap.xml", SitemapController, :sitemap
    get "/robots.txt", SitemapController, :robots
    get "/.well-known/site.standard.publication", StandardController, :publication
  end

  scope "/", NewtonWeb do
    pipe_through :api

    get "/.well-known/oauth-authorization-server", OAuthController, :authorization_server_metadata
    post "/oauth/register", OAuthController, :register
    post "/oauth/token", OAuthController, :token
  end

  # No pipeline: anubis owns auth and content negotiation for these routes,
  # and the browser plugs would CSRF-reject POSTs and break SSE.
  scope "/" do
    forward "/mcp", Anubis.Server.Transport.StreamableHTTP.Plug, server: Newton.MCP.Server

    forward "/.well-known/oauth-protected-resource", Anubis.Server.Transport.WellKnown,
      server: Newton.MCP.Server
  end

  scope "/admin", NewtonWeb.Admin do
    pipe_through [:browser, :require_authenticated_user, :admin_csp]

    live_session :admin,
      on_mount: [{NewtonWeb.UserAuth, :require_authenticated}],
      root_layout: {NewtonWeb.Layouts, :admin_root} do
      live "/", DashboardLive, :index
      live "/posts", PostLive.Index, :index
      live "/posts/new", PostLive.Editor, :new
      live "/posts/:id/edit", PostLive.Editor, :edit
      live "/reading", ReadingLive.Index, :index
      live "/reading/new", ReadingLive.Index, :new
      live "/reading/:id/edit", ReadingLive.Index, :edit
      live "/photos", GalleryLive.Index, :index
      live "/photos/new", GalleryLive.Index, :new
      live "/photos/:id", GalleryLive.Show, :show
      live "/photos/:id/edit", GalleryLive.Show, :settings
      live "/photos/:id/photo/:photo_id", GalleryLive.Show, :photo
      live "/media", MediaLive, :index
    end

    # Managing credentials is sensitive: require a recent authentication (sudo
    # mode), so a hijacked or unattended session can't silently plant a passkey.
    live_session :admin_sudo,
      on_mount: [
        {NewtonWeb.UserAuth, :require_authenticated},
        {NewtonWeb.UserAuth, :require_sudo_mode}
      ],
      root_layout: {NewtonWeb.Layouts, :admin_root} do
      live "/settings", SettingsLive, :edit
    end
  end

  # The sudo re-authentication surface. Authenticated but deliberately NOT
  # sudo-gated (that would loop), so a stale session can re-confirm here.
  scope "/", NewtonWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :sudo_reauth,
      on_mount: [{NewtonWeb.UserAuth, :require_authenticated}],
      root_layout: {NewtonWeb.Layouts, :admin_root} do
      live "/login/confirm-access", UserLive.Sudo, :new
    end

    post "/login/confirm-access", SudoController, :password
    post "/login/confirm-access/passkey", SudoController, :passkey
  end

  scope "/", NewtonWeb do
    pipe_through [:browser, :require_authenticated_user, :require_sudo_mode]

    get "/oauth/authorize", OAuthAuthorizationController, :authorize
    post "/oauth/authorize", OAuthAuthorizationController, :approve
  end

  # Other scopes may use custom stacks.
  # scope "/api", NewtonWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:newton, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: NewtonWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", NewtonWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{NewtonWeb.UserAuth, :mount_current_scope}],
      root_layout: {NewtonWeb.Layouts, :admin_root} do
      live "/login", UserLive.Login, :new
      live "/login/verify", UserLive.Verify, :new
    end

    post "/login", UserSessionController, :create
    post "/login/verify/recovery", UserSessionController, :recovery_login
    get "/login/passkey/challenge", UserSessionController, :passkey_challenge
    post "/login/passkey", UserSessionController, :passkey_login
    delete "/logout", UserSessionController, :delete
  end

  if Application.compile_env(:newton, :dev_routes) do
    use ErrorTracker.Web, :router

    scope "/dev" do
      pipe_through :browser

      error_tracker_dashboard "/errors"
    end
  end
end
