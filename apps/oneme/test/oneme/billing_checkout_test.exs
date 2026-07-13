defmodule Oneme.BillingCheckoutTest do
  use Oneme.DataCase

  alias Oneme.Access
  alias Oneme.Billing
  alias Oneme.Operations.{AuditLog, UsageEvent}
  alias Oneme.Repo

  test "creates a hosted checkout session and records operational events" do
    assert {:ok, team} = Access.create_team(%{name: "Checkout team", slug: "checkout-team"})
    {server, port} = start_json_server()
    previous_url = System.get_env("ONEME_BILLING_CHECKOUT_URL")
    previous_http = System.get_env("ONEME_BILLING_ALLOW_INSECURE_HTTP")
    System.put_env("ONEME_BILLING_CHECKOUT_URL", "http://127.0.0.1:#{port}")
    System.put_env("ONEME_BILLING_ALLOW_INSECURE_HTTP", "true")

    on_exit(fn ->
      restore_env("ONEME_BILLING_CHECKOUT_URL", previous_url)
      restore_env("ONEME_BILLING_ALLOW_INSECURE_HTTP", previous_http)
      send(server, :stop)
    end)

    assert {:ok, session} =
             Billing.create_checkout_session(team.id, %{
               "planSlug" => "free",
               "successUrl" => "https://app.example/checkout/success",
               "cancelUrl" => "https://app.example/checkout/cancel",
               "idempotencyKey" => "team-#{team.id}-checkout-1"
             })

    assert session.provider == "test-billing"
    assert session.session_id == "cs_test_123"

    assert %UsageEvent{metadata: %{"planSlug" => "free", "sessionId" => "cs_test_123"}} =
             Repo.get_by(UsageEvent,
               event_type: "billing_checkout_requested",
               subject_id: to_string(team.id)
             )

    assert %AuditLog{action: "billing_checkout_requested"} =
             Repo.get_by(AuditLog,
               action: "billing_checkout_requested",
               resource_id: to_string(team.id)
             )

    assert_receive {:provider_request, request}, 1_000
    assert String.contains?(request, "subscription_checkout")
    assert String.contains?(request, "monthlyPriceCents")
  end

  test "requires secure return URLs and an idempotency key" do
    assert {:ok, team} =
             Access.create_team(%{name: "Checkout validation", slug: "checkout-validation"})

    assert {:error, :invalid_return_url} =
             Billing.create_checkout_session(team.id, %{
               "successUrl" => "http://app.example/success",
               "cancelUrl" => "https://app.example/cancel",
               "idempotencyKey" => "checkout-validation"
             })

    assert {:error, :idempotency_key_required} =
             Billing.create_checkout_session(team.id, %{
               "successUrl" => "https://app.example/success",
               "cancelUrl" => "https://app.example/cancel"
             })
  end

  defp start_json_server do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_address, port}} = :inet.sockname(listener)
    parent = self()

    pid =
      spawn(fn ->
        {:ok, socket} = :gen_tcp.accept(listener)
        {:ok, request} = :gen_tcp.recv(socket, 0, 5_000)
        send(parent, {:provider_request, request})

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

        receive do
          :stop -> :ok
        after
          100 -> :ok
        end
      end)

    {pid, port}
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
