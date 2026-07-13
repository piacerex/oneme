defmodule Oneme.AccessTest do
  use Oneme.DataCase

  alias Oneme.Access

  test "creates one-time API key material and authenticates its hash" do
    assert {:ok, team} = Access.create_team(%{name: "Acme", slug: "acme"})
    assert {:ok, api_key, raw_key} = Access.create_api_key(team.id, %{name: "CI", role: "editor"})

    refute api_key.key_hash == raw_key
    assert api_key.key_prefix == String.slice(raw_key, 0, 14)
    assert {:ok, principal} = Access.authenticate_api_key(raw_key)
    assert principal.team_id == team.id
    assert principal.role == "editor"
    assert Access.authorized?(principal, "viewer")
    assert Access.authorized?(principal, "editor")
    refute Access.authorized?(principal, "owner")
    assert {:error, :invalid_api_key} = Access.authenticate_api_key("oneme_invalid")
  end

  test "revoked API keys stop authenticating" do
    assert {:ok, team} = Access.create_team(%{name: "Revocation", slug: "revocation"})
    assert {:ok, api_key, raw_key} = Access.create_api_key(team.id)
    assert {:ok, _revoked} = Access.revoke_api_key(api_key.id)
    assert {:error, :invalid_api_key} = Access.authenticate_api_key(raw_key)
  end
end
