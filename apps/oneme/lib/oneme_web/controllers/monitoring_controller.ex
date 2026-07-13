defmodule OnemeWeb.MonitoringController do
  use OnemeWeb, :controller

  alias Oneme.Access
  alias Oneme.CdnMonitor

  def cdn(conn, _params) do
    case conn.assigns[:principal] do
      principal when is_map(principal) ->
        if Access.authorized?(principal, "admin"),
          do: json(conn, CdnMonitor.check_now()),
          else: forbidden(conn)

      _ ->
        forbidden(conn)
    end
  end

  defp forbidden(conn), do: conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
end
