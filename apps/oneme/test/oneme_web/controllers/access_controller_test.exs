defmodule OnemeWeb.AccessControllerTest do
  use OnemeWeb.ConnCase

  alias Oneme.Access

  test "reports the anonymous development auth state", %{conn: conn} do
    response = conn |> get("/api/auth/me") |> json_response(200)

    assert response["authenticated"] == false
    assert response["authRequired"] == false
  end

  test "enforces API key roles on avatar writes", %{conn: conn} do
    assert {:ok, team} = Access.create_team(%{name: "Viewer team", slug: "viewer-team"})
    assert {:ok, _api_key, raw_key} = Access.create_api_key(team.id, %{role: "viewer"})

    response =
      conn
      |> put_req_header("authorization", "Bearer #{raw_key}")
      |> post("/api/avatars", %{"name" => "Denied", "config" => %{}})
      |> json_response(403)

    assert response["error"] == "forbidden"
  end

  test "returns an authenticated principal and permits editor writes", %{conn: conn} do
    assert {:ok, team} = Access.create_team(%{name: "Editor team", slug: "editor-team"})
    assert {:ok, _api_key, raw_key} = Access.create_api_key(team.id, %{role: "editor"})

    response =
      conn
      |> put_req_header("x-oneme-api-key", raw_key)
      |> get("/api/auth/me")
      |> json_response(200)

    assert response["authenticated"] == true
    assert response["principal"]["teamId"] == team.id
    assert response["principal"]["role"] == "editor"

    avatar =
      build_conn()
      |> put_req_header("x-oneme-api-key", raw_key)
      |> post("/api/avatars", %{"name" => "Allowed", "config" => %{}})
      |> json_response(201)

    assert avatar["teamId"] == team.id
  end
end
