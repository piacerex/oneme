defmodule Oneme.BillingCheckoutProviderTest do
  use Oneme.DataCase

  alias Oneme.Billing.CheckoutProvider

  test "requires a configured checkout provider" do
    previous_url = System.get_env("ONEME_BILLING_CHECKOUT_URL")
    System.delete_env("ONEME_BILLING_CHECKOUT_URL")
    on_exit(fn -> restore_env("ONEME_BILLING_CHECKOUT_URL", previous_url) end)

    assert {:error, :not_configured} = CheckoutProvider.create(%{}, "checkout-request")
  end

  test "posts a card-free checkout request and normalizes the hosted session" do
    {server, port} = start_json_server()
    previous_url = System.get_env("ONEME_BILLING_CHECKOUT_URL")
    previous_http = System.get_env("ONEME_BILLING_ALLOW_INSECURE_HTTP")
    previous_key = System.get_env("ONEME_BILLING_CHECKOUT_API_KEY")
    System.put_env("ONEME_BILLING_CHECKOUT_URL", "http://127.0.0.1:#{port}")
    System.put_env("ONEME_BILLING_ALLOW_INSECURE_HTTP", "true")
    System.put_env("ONEME_BILLING_CHECKOUT_API_KEY", "checkout-secret")

    on_exit(fn ->
      restore_env("ONEME_BILLING_CHECKOUT_URL", previous_url)
      restore_env("ONEME_BILLING_ALLOW_INSECURE_HTTP", previous_http)
      restore_env("ONEME_BILLING_CHECKOUT_API_KEY", previous_key)
      send(server, :stop)
    end)

    assert {:ok,
            %{
              provider: "test-billing",
              session_id: "cs_test_123",
              checkout_url: "https://checkout.example/session/cs_test_123",
              status: "pending"
            }} =
             CheckoutProvider.create(
               %{
                 "kind" => "subscription_checkout",
                 "cardNumber" => "must-not-be-sent"
               },
               "checkout-request"
             )

    assert_receive {:provider_request, request}, 1_000
    request = String.downcase(request)
    assert String.contains?(request, "authorization: bearer checkout-secret")
    assert String.contains?(request, "x-oneme-api-version: v1")
    assert String.contains?(request, "idempotency-key: checkout-request")
    refute String.contains?(request, "must-not-be-sent")
  end

  test "rejects a non-https checkout URL from the provider" do
    {server, port} = start_json_server(%{"checkoutUrl" => "http://checkout.example/session"})
    previous_url = System.get_env("ONEME_BILLING_CHECKOUT_URL")
    previous_http = System.get_env("ONEME_BILLING_ALLOW_INSECURE_HTTP")
    System.put_env("ONEME_BILLING_CHECKOUT_URL", "http://127.0.0.1:#{port}")
    System.put_env("ONEME_BILLING_ALLOW_INSECURE_HTTP", "true")

    on_exit(fn ->
      restore_env("ONEME_BILLING_CHECKOUT_URL", previous_url)
      restore_env("ONEME_BILLING_ALLOW_INSECURE_HTTP", previous_http)
      send(server, :stop)
    end)

    assert {:error, :provider_invalid_response, _message} =
             CheckoutProvider.create(%{}, "checkout-request")
  end

  defp start_json_server(overrides \\ %{}) do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_address, port}} = :inet.sockname(listener)
    parent = self()

    pid =
      spawn(fn ->
        {:ok, socket} = :gen_tcp.accept(listener)
        {:ok, request} = :gen_tcp.recv(socket, 0, 5_000)
        send(parent, {:provider_request, request})

        body =
          Jason.encode!(
            Map.merge(
              %{
                "provider" => "test-billing",
                "sessionId" => "cs_test_123",
                "checkoutUrl" => "https://checkout.example/session/cs_test_123",
                "status" => "pending"
              },
              overrides
            )
          )

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
