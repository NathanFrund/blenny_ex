defmodule BlennyExampleAppWeb.Router do
  use BlennyExampleAppWeb, :router
  import Blenny.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug Blenny.Plug.FetchSession
    plug :fetch_live_flash
    plug :put_root_layout, html: {BlennyExampleAppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", BlennyExampleAppWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/" do
    pipe_through :browser

    blenny_modules("")
  end

  # SSE endpoint — no browser pipeline, fully-qualified module
  get "/sse", Blenny.Transport.SSEPlug, []

  # Other scopes may use custom stacks.
  # scope "/api", BlennyExampleAppWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:blenny_example_app, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BlennyExampleAppWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
