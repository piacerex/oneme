defmodule Oneme.WebhooksTest do
  use Oneme.DataCase

  alias Oneme.Access
  alias Oneme.Webhooks

  test "stores encrypted webhook secrets and creates signed delivery records" do
    assert {:ok, team} = Access.create_team(%{name: "Webhook team", slug: "webhook-team"})

    assert {:ok, endpoint, raw_secret} =
             Webhooks.create_endpoint(team.id, %{
               "name" => "Avatar events",
               "url" => "https://example.com/oneme",
               "events" => ["avatar.exported"]
             })

    refute endpoint.secret_ciphertext =~ raw_secret
    assert String.starts_with?(raw_secret, "whsec_")

    assert {:ok, delivery} =
             Webhooks.create_test_delivery(endpoint, "avatar.exported", %{"avatarId" => 42})

    assert delivery.status == "queued"
    assert String.starts_with?(delivery.signature, "sha256=")
    refute delivery.signature =~ raw_secret
  end

  test "marks an unreachable explicit delivery as failed and increments attempts" do
    assert {:ok, team} = Access.create_team(%{name: "Delivery team", slug: "delivery-team"})

    assert {:ok, endpoint, _raw_secret} =
             Webhooks.create_endpoint(team.id, %{"url" => "http://127.0.0.1:1"})

    assert {:ok, delivery} = Webhooks.create_test_delivery(endpoint, "avatar.exported", %{})
    assert {:ok, failed} = Webhooks.deliver(delivery.id)
    assert failed.status == "failed"
    assert failed.attempts == 1
    assert failed.error_message
  end
end
