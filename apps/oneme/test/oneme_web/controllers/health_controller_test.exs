defmodule OnemeWeb.HealthControllerTest do
  use OnemeWeb.ConnCase

  test "reports application and database health", %{conn: conn} do
    response = conn |> get(~p"/api/health") |> json_response(200)

    assert response["service"] == "oneme"
    assert response["status"] == "ok"
    assert response["database"] == "ok"
  end
end
