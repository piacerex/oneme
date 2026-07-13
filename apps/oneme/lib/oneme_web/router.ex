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
    plug OnemeWeb.RateLimit
  end

  pipeline :billing_webhook do
    plug :accepts, ["json"]
    plug OnemeWeb.RateLimit
  end

  scope "/", OnemeWeb do
    pipe_through :browser

    live "/", BuilderLive
    live "/builder", BuilderLive
    live "/widget", BuilderLive
    live "/avatars/:id", PublicAvatarLive
    live "/admin/audit-logs", AdminAuditLive
  end

  scope "/api", OnemeWeb do
    pipe_through :api

    get "/health", HealthController, :show
    get "/auth/me", AccessController, :me
    post "/auth/bootstrap", AccessController, :bootstrap
    post "/auth/api-keys", AccessController, :create_api_key
    delete "/auth/api-keys/:id", AccessController, :revoke_api_key
    get "/usage", UsageController, :index
    get "/billing", BillingController, :show
    get "/billing/invoices", BillingController, :invoices
    post "/billing/checkout", BillingController, :checkout
    patch "/billing/subscription", BillingController, :update_subscription
    post "/billing/plans", BillingController, :create_plan
    get "/webhooks", WebhookController, :index
    post "/webhooks", WebhookController, :create
    post "/webhooks/:id/test", WebhookController, :test_delivery
    post "/webhook-deliveries/:id/retry", WebhookController, :retry_delivery
    get "/audit-logs", AuditController, :index
    post "/audit-logs/retention", AuditController, :prune
    get "/parts", AssetsController, :index
    get "/assets/integrity", AssetsController, :integrity
    post "/assets/inspect", AssetsController, :inspect_all
    post "/assets/:asset_key/inspect", AssetsController, :inspect_asset
    get "/monitoring/cdn", MonitoringController, :cdn
    post "/face-analysis-jobs", FaceAnalysisController, :create
    get "/face-analysis-jobs/:id", FaceAnalysisController, :show
    post "/face-completion", FaceCompletionController, :create
    post "/avatars/from-face-analysis", FaceAnalysisController, :create_avatar
    post "/avatars", AvatarController, :create
    patch "/avatars/:id", AvatarController, :update
    post "/generation-jobs", GenerationJobController, :create
    get "/generation-jobs/:id", GenerationJobController, :show
    post "/generation-jobs/:id/feedback", GenerationJobController, :feedback
    post "/generation-jobs/:id/retry", GenerationJobController, :retry
    post "/generation-jobs/:id/regenerate", GenerationJobController, :regenerate
    post "/export-jobs", ExportJobController, :create
    get "/export-jobs/:id", ExportJobController, :show
    post "/export-jobs/:id/retry", ExportJobController, :retry
    get "/avatars/:id", AvatarController, :show
    get "/avatars/:id/config", AvatarController, :config
    get "/avatars/:id/public", AvatarController, :public
    post "/avatars/:id/exports", AvatarController, :export
    get "/avatars/:id/model", AvatarController, :model
  end

  scope "/api/billing", OnemeWeb do
    pipe_through :billing_webhook

    post "/webhooks/:provider", BillingController, :provider_webhook
  end

  # Other scopes may use custom stacks.
  # scope "/api", OnemeWeb do
  #   pipe_through :api
  # end
end
