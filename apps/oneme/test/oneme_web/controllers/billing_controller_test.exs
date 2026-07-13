defmodule OnemeWeb.BillingControllerTest do
  use OnemeWeb.ConnCase

  alias Oneme.Access
  alias Oneme.Billing.ProviderWebhook

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

  test "accepts a signed provider event and exposes the invoice to admins", %{conn: conn} do
    assert {:ok, result, raw_key} =
             Access.bootstrap(%{
               team_name: "Provider webhook team",
               team_slug: "provider-webhook-team",
               external_id: "provider-webhook-owner"
             })

    event = %{
      "id" => "evt_controller_invoice_1",
      "type" => "invoice.paid",
      "teamId" => result.team.id,
      "invoice" => %{
        "id" => "invoice_controller_1",
        "total" => 2500,
        "amountPaid" => 2500,
        "currency" => "jpy"
      }
    }

    body = Jason.encode!(event)
    Application.put_env(:oneme, :billing_webhook_secrets, %{"mock" => "test-secret"})

    on_exit(fn -> Application.delete_env(:oneme, :billing_webhook_secrets) end)

    response =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header(
        "x-oneme-billing-signature",
        ProviderWebhook.signature("test-secret", body)
      )
      |> post("/api/billing/webhooks/mock", event)
      |> json_response(200)

    assert response == %{"duplicate" => false, "received" => true}

    invoices =
      build_conn()
      |> put_req_header("x-oneme-api-key", raw_key)
      |> get("/api/billing/invoices")
      |> json_response(200)

    assert [%{"externalId" => "invoice_controller_1", "status" => "paid"}] = invoices["invoices"]
  end
end
