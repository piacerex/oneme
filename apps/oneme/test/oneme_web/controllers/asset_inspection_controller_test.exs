defmodule OnemeWeb.AssetInspectionControllerTest do
  use OnemeWeb.ConnCase

  alias Oneme.Access

  test "admin can inspect seeded procedural assets", %{conn: conn} do
    assert {:ok, _result, raw_key} =
             Access.bootstrap(%{
               team_name: "Asset inspection API",
               team_slug: "asset-inspection-api",
               external_id: "asset-inspection-owner"
             })

    response =
      conn
      |> put_req_header("x-oneme-api-key", raw_key)
      |> post("/api/assets/inspect")
      |> json_response(200)

    assert length(response["assets"]) >= 18
    assert Enum.all?(response["assets"], &(&1["inspectionStatus"] == "passed"))
  end
end
