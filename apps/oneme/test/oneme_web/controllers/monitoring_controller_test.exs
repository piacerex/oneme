defmodule OnemeWeb.MonitoringControllerTest do
  use OnemeWeb.ConnCase

  alias Oneme.Access

  test "admin can read an unconfigured CDN monitoring report", %{conn: conn} do
    previous = System.get_env("ONEME_CDN_URLS")
    System.delete_env("ONEME_CDN_URLS")
    on_exit(fn -> restore_env("ONEME_CDN_URLS", previous) end)

    assert {:ok, _result, raw_key} =
             Access.bootstrap(%{
               team_name: "CDN monitoring API",
               team_slug: "cdn-monitoring-api",
               external_id: "cdn-monitoring-owner"
             })

    response =
      conn
      |> put_req_header("x-oneme-api-key", raw_key)
      |> get("/api/monitoring/cdn")
      |> json_response(200)

    assert response["status"] == "not_configured"
    assert response["endpoints"] == []
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
