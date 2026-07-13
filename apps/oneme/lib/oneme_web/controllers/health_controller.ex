defmodule OnemeWeb.HealthController do
  use OnemeWeb, :controller

  alias Oneme.Operations

  def show(conn, _params) do
    health = Operations.health()
    status = if health.status == "ok", do: :ok, else: :service_unavailable

    conn
    |> put_status(status)
    |> json(Map.put(health, :service, "oneme"))
  end
end
