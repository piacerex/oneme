defmodule OnemeWeb.AvatarControllerTest do
  use OnemeWeb.ConnCase

  alias Oneme.Avatars

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
end
