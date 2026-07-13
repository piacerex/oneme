defmodule OnemeWeb.AvatarControllerTest do
  use OnemeWeb.ConnCase

  alias Oneme.Avatars

  test "creates and updates an avatar through the API", %{conn: conn} do
    config = %{"parts" => %{"face" => "face.soft_01"}, "colors" => %{"skin" => "#d5a083"}}

    response =
      conn
      |> post("/api/avatars", %{"name" => "API avatar", "config" => config})
      |> json_response(201)

    assert response["name"] == "API avatar"
    assert response["config"] == config

    response =
      build_conn()
      |> patch("/api/avatars/#{response["id"]}", %{"name" => "Updated API avatar"})
      |> json_response(200)

    assert response["name"] == "Updated API avatar"
  end

  test "rejects unsupported avatar part values", %{conn: conn} do
    response =
      conn
      |> post("/api/avatars", %{
        "name" => "Invalid avatar",
        "config" => %{"parts" => %{"face" => "face.unknown"}}
      })
      |> json_response(422)

    assert response["error"] =~ "not a supported part"
  end

  test "returns the database asset catalog", %{conn: conn} do
    response = conn |> get("/api/parts") |> json_response(200)
    face = Enum.find(response["parts"], &(&1["partId"] == "face.soft_01"))

    assert length(response["parts"]) >= 18
    assert face["asset"]["origin"] == %{"x" => 0.0, "y" => 0.0, "z" => 0.0}
    assert face["asset"]["redistributable"] == true
  end

  test "returns a public avatar response", %{conn: conn} do
    {:ok, avatar} =
      Avatars.create_avatar(%{
        name: "Public avatar",
        config: %{"parts" => %{"baseBody" => "body.basic_01"}},
        visibility: "public"
      })

    response = conn |> get("/api/avatars/#{avatar.id}/public") |> json_response(200)

    assert response["avatarId"] == avatar.id
    assert response["visibility"] == "public"
    assert response["configUrl"] =~ "/api/avatars/#{avatar.id}/config"
  end

  test "does not expose private avatars publicly", %{conn: conn} do
    {:ok, avatar} =
      Avatars.create_avatar(%{
        name: "Private avatar",
        config: %{},
        visibility: "private"
      })

    assert conn |> get("/api/avatars/#{avatar.id}/public") |> response(404) == "avatar is private"
  end

  test "does not export a private avatar model", %{conn: conn} do
    {:ok, avatar} =
      Avatars.create_avatar(%{
        name: "Private model avatar",
        config: %{},
        visibility: "private"
      })

    assert conn |> get("/api/avatars/#{avatar.id}/model?format=glb") |> response(404) ==
             "avatar is private"
  end
end
