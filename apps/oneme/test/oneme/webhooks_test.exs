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
end
