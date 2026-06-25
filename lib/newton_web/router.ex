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

  # Social card images. No :browser pipeline — these are PNGs, so we skip
  # accepts/session/CSRF and let the controller set content-type + caching.
  scope "/og", NewtonWeb do
    get "/posts/:slug", OgImageController, :show
  end

  scope "/admin", NewtonWeb.Admin do
    pipe_through [:browser, :require_authenticated_user]

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
      live "/settings", SettingsLive, :edit
    end
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
end
