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
    plug OnemeWeb.APIAuth
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
    get "/auth/me", AccessController, :me
    post "/auth/bootstrap", AccessController, :bootstrap
    post "/auth/api-keys", AccessController, :create_api_key
    delete "/auth/api-keys/:id", AccessController, :revoke_api_key
    get "/parts", AssetsController, :index
    post "/avatars", AvatarController, :create
    patch "/avatars/:id", AvatarController, :update
    post "/generation-jobs", GenerationJobController, :create
    get "/generation-jobs/:id", GenerationJobController, :show
    post "/generation-jobs/:id/feedback", GenerationJobController, :feedback
    post "/export-jobs", ExportJobController, :create
    get "/export-jobs/:id", ExportJobController, :show
    post "/export-jobs/:id/retry", ExportJobController, :retry
    get "/avatars/:id", AvatarController, :show
    get "/avatars/:id/config", AvatarController, :config
    get "/avatars/:id/public", AvatarController, :public
    post "/avatars/:id/exports", AvatarController, :export
    get "/avatars/:id/model", AvatarController, :model
  end

  # Other scopes may use custom stacks.
  # scope "/api", OnemeWeb do
  #   pipe_through :api
  # end
end
