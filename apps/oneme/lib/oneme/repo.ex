defmodule Oneme.Repo do
  use Ecto.Repo,
    otp_app: :oneme,
    adapter: Ecto.Adapters.Postgres
end
