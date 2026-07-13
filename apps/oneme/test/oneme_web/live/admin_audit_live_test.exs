defmodule OnemeWeb.AdminAuditLiveTest do
  use OnemeWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Oneme.Access
  alias Oneme.Operations

  test "renders audit logs and refreshes them", %{conn: conn} do
    assert {:ok, _audit} =
             Operations.record_audit(
               "avatar.exported",
               %{
                 resource_type: "avatar",
                 resource_id: 42,
                 metadata: %{"format" => "glb"}
               }
             )

    {:ok, view, html} = live(conn, ~p"/admin/audit-logs")

    assert html =~ "監査ログ"
    assert has_element?(view, ".audit-table")
    assert html =~ "avatar.exported"
    assert html =~ "glb"

    assert render_click(view, "refresh") =~ "監査ログを更新しました。"
  end

  test "authenticates an admin key when auth is required", %{conn: conn} do
    System.put_env("ONEME_AUTH_REQUIRED", "true")

    on_exit(fn -> System.delete_env("ONEME_AUTH_REQUIRED") end)

    assert {:ok, result, raw_key} =
             Access.bootstrap(%{
               team_name: "Audit UI team",
               team_slug: "audit-ui-#{System.unique_integer([:positive])}",
               external_id: "audit-ui-owner-#{System.unique_integer([:positive])}"
             })

    assert {:ok, _audit} =
             Operations.record_audit("admin.login", %{resource_id: result.team.id})

    {:ok, view, html} = live(conn, ~p"/admin/audit-logs")
    assert html =~ "管理者APIキーで認証してください。"

    html = render_submit(view, "authenticate", %{"api_key" => raw_key})
    assert html =~ "admin.login"
    refute html =~ "管理者APIキーで認証してください。"
  end
end
