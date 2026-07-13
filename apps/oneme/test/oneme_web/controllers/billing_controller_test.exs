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

  test "owner can request a hosted checkout session", %{conn: conn} do
    assert {:ok, _result, raw_key} =
             Access.bootstrap(%{
               team_name: "Checkout controller team",
               team_slug: "checkout-controller-team",
               external_id: "checkout-controller-owner"
             })

    {server, port} = start_checkout_server()
    previous_url = System.get_env("ONEME_BILLING_CHECKOUT_URL")
    previous_http = System.get_env("ONEME_BILLING_ALLOW_INSECURE_HTTP")
    System.put_env("ONEME_BILLING_CHECKOUT_URL", "http://127.0.0.1:#{port}")
    System.put_env("ONEME_BILLING_ALLOW_INSECURE_HTTP", "true")

    on_exit(fn ->
      restore_env("ONEME_BILLING_CHECKOUT_URL", previous_url)
      restore_env("ONEME_BILLING_ALLOW_INSECURE_HTTP", previous_http)
      send(server, :stop)
    end)

    response =
      conn
      |> put_req_header("x-oneme-api-key", raw_key)
      |> post("/api/billing/checkout", %{
        "planSlug" => "free",
        "successUrl" => "https://app.example/success",
        "cancelUrl" => "https://app.example/cancel",
        "idempotencyKey" => "controller-checkout-1"
      })
      |> json_response(200)

    assert response["provider"] == "test-billing"
    assert response["sessionId"] == "cs_test_123"
    assert response["checkoutUrl"] == "https://checkout.example/session/cs_test_123"
    assert response["status"] == "pending"
  end

  defp start_checkout_server do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_address, port}} = :inet.sockname(listener)

    pid =
      spawn(fn ->
        {:ok, socket} = :gen_tcp.accept(listener)
        {:ok, _request} = :gen_tcp.recv(socket, 0, 5_000)

        body =
          Jason.encode!(%{
            "provider" => "test-billing",
            "sessionId" => "cs_test_123",
            "checkoutUrl" => "https://checkout.example/session/cs_test_123",
            "status" => "pending"
          })

        response =
          "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n#{body}"

        :gen_tcp.send(socket, response)
        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
      end)

    {pid, port}
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
