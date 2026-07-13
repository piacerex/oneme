defmodule OnemeWeb.AssetsIntegrityControllerTest do
  use OnemeWeb.ConnCase

  alias Oneme.Access

  test "admin can inspect the asset integrity report", %{conn: conn} do
    assert {:ok, _result, raw_key} =
             Access.bootstrap(%{
               team_name: "Asset ops",
               team_slug: "asset-ops",
               external_id: "asset-ops-owner"
             })

    response =
      conn
      |> put_req_header("authorization", "Bearer #{raw_key}")
      |> get("/api/assets/integrity")
      |> json_response(200)

    assert response["status"] == "ok"
    assert response["reviewCount"] == 0
    assert response["assetCount"] >= 18
  end
end
