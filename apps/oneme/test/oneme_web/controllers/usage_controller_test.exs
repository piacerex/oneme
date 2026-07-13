defmodule OnemeWeb.UsageControllerTest do
  use OnemeWeb.ConnCase

  alias Oneme.Access
  alias Oneme.Usage

  test "admin can read team usage summaries", %{conn: conn} do
    assert {:ok, result, raw_key} =
             Access.bootstrap(%{
               team_name: "Usage API team",
               team_slug: "usage-api-team",
               external_id: "usage-api-owner"
             })

    assert :ok = Usage.record(result.team.id, "export_requested", 4)

    response =
      conn
      |> put_req_header("authorization", "Bearer #{raw_key}")
      |> get("/api/usage")
      |> json_response(200)

    assert response["teamId"] == result.team.id
    assert response["metrics"]["export_requested"] == 4
    assert response["from"]
    assert response["to"]
  end

  test "viewer cannot read team usage summaries", %{conn: conn} do
    assert {:ok, team} = Access.create_team(%{name: "Usage viewer", slug: "usage-viewer"})
    assert {:ok, _api_key, raw_key} = Access.create_api_key(team.id, %{role: "viewer"})

    response =
      conn
      |> put_req_header("x-oneme-api-key", raw_key)
      |> get("/api/usage")
      |> json_response(403)

    assert response["error"] == "forbidden"
  end
end
