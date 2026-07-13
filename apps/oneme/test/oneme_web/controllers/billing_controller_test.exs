defmodule OnemeWeb.BillingControllerTest do
  use OnemeWeb.ConnCase

  alias Oneme.Access

  test "admin can read and update team billing contract", %{conn: conn} do
    assert {:ok, _result, raw_key} =
             Access.bootstrap(%{
               team_name: "Billing API team",
               team_slug: "billing-api-team",
               external_id: "billing-api-owner"
             })

    response =
      conn
      |> put_req_header("x-oneme-api-key", raw_key)
      |> get("/api/billing")
      |> json_response(200)

    assert response["plan"]["slug"] == "free"
    assert Enum.any?(response["plans"], &(&1["slug"] == "free"))
    assert response["subscription"]["provider"] == "manual"
    assert response["remaining"]["export_requested"] == 10

    updated =
      build_conn()
      |> put_req_header("x-oneme-api-key", raw_key)
      |> patch("/api/billing/subscription", %{"planSlug" => "free", "status" => "trialing"})
      |> json_response(200)

    assert updated["subscription"]["status"] == "trialing"
  end
end
