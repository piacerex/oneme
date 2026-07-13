defmodule Oneme.OperationsTest do
  use Oneme.DataCase

  alias Oneme.Operations
  alias Oneme.Operations.{AuditLog, UsageEvent}

  test "reports database health" do
    assert %{status: "ok", database: "ok"} = Operations.health()
  end

  test "records usage and audit metadata without source images" do
    assert {:ok, usage} =
             Operations.record_usage("public_avatar_read", %{
               subject_type: "avatar",
               subject_id: 42,
               metadata: %{"format" => "vrm"}
             })

    assert usage.event_type == "public_avatar_read"
    assert usage.subject_id == "42"
    assert usage.metadata == %{"format" => "vrm"}

    assert {:ok, audit} =
             Operations.record_audit("avatar_published", %{
               resource_type: "avatar",
               resource_id: 42
             })

    assert audit.action == "avatar_published"
    assert audit.resource_id == "42"
    assert audit.metadata == %{}
    assert Repo.aggregate(UsageEvent, :count) == 1
    assert Repo.aggregate(AuditLog, :count) == 1
  end
end
