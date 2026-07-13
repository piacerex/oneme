defmodule OnemeWeb.AccessControllerManagementTest do
  use OnemeWeb.ConnCase

  alias Oneme.Access

  test "bootstraps a team and returns the raw API key once", %{conn: conn} do
    response =
      conn
      |> post("/api/auth/bootstrap", %{
        "teamName" => "Bootstrap team",
        "teamSlug" => "bootstrap-team",
        "externalId" => "bootstrap-user",
        "email" => "bootstrap@example.invalid",
        "userName" => "Bootstrap owner"
      })
      |> json_response(201)

    assert response["team"]["slug"] == "bootstrap-team"
    assert response["user"]["email"] == "bootstrap@example.invalid"
    assert String.starts_with?(response["apiKey"], "oneme_")

    me =
      build_conn()
      |> put_req_header("x-oneme-api-key", response["apiKey"])
      |> get("/api/auth/me")
      |> json_response(200)

    assert me["principal"]["role"] == "owner"
  end

  test "owner can create and revoke a team API key", %{conn: conn} do
    assert {:ok, result, owner_key} =
             Access.bootstrap(%{
               team_name: "Key team",
               team_slug: "key-team",
               external_id: "key-owner"
             })

    response =
      conn
      |> put_req_header("authorization", "Bearer #{owner_key}")
      |> post("/api/auth/api-keys", %{
        "teamId" => to_string(result.team.id),
        "name" => "Viewer key",
        "role" => "viewer"
      })
      |> json_response(201)

    assert response["role"] == "viewer"
    assert response["teamId"] == result.team.id

    assert conn
           |> put_req_header("authorization", "Bearer #{owner_key}")
           |> delete("/api/auth/api-keys/#{response["apiKeyId"]}")
           |> response(204) == ""

    assert {:error, :invalid_api_key} = Access.authenticate_api_key(response["apiKey"])
  end
end
