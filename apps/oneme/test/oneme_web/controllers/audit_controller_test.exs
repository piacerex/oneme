defmodule OnemeWeb.AuditControllerTest do
  use OnemeWeb.ConnCase

  alias Oneme.Access
  alias Oneme.Operations

  test "admin can list audit records without source image data", %{conn: conn} do
    assert {:ok, _result, raw_key} =
             Access.bootstrap(%{
               team_name: "Audit API team",
               team_slug: "audit-api-team",
               external_id: "audit-api-owner"
             })

    assert :ok =
             Operations.track_audit("avatar_exported", %{
               resource_type: "avatar",
               resource_id: 42,
               metadata: %{"format" => "vrm"}
             })

    response =
      conn
      |> put_req_header("authorization", "Bearer #{raw_key}")
      |> get("/api/audit-logs?limit=10")
      |> json_response(200)

    audit = Enum.find(response["audits"], &(&1["action"] == "avatar_exported"))
    assert audit["metadata"] == %{"format" => "vrm"}
    refute Jason.encode!(audit) =~ "face"
  end
end
