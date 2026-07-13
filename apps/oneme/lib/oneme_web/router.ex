defmodule OnemeWeb.Router do
  use OnemeWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {OnemeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", OnemeWeb do
    pipe_through :browser

    live "/", BuilderLive
    live "/builder", BuilderLive
    live "/widget", BuilderLive
    live "/avatars/:id", PublicAvatarLive
  end

  scope "/api", OnemeWeb do
    pipe_through :api

    get "/health", HealthController, :show
    post "/export-jobs", ExportJobController, :create
    get "/export-jobs/:id", ExportJobController, :show
    get "/avatars/:id", AvatarController, :show
    get "/avatars/:id/config", AvatarController, :config
    get "/avatars/:id/public", AvatarController, :public
  end

  # Other scopes may use custom stacks.
  # scope "/api", OnemeWeb do
  #   pipe_through :api
  # end
end
