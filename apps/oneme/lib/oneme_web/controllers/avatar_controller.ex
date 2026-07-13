defmodule OnemeWeb.AvatarController do
  use OnemeWeb, :controller

  alias Oneme.Avatars

  def show(conn, %{"id" => id}) do
    conn |> json(serialize(Avatars.get_avatar!(id)))
  end

  def config(conn, %{"id" => id}) do
    avatar = Avatars.get_avatar!(id)
    conn |> json(%{avatarId: avatar.id, config: avatar.config, updatedAt: avatar.updated_at})
  end

  def public(conn, %{"id" => id}) do
    avatar = Avatars.get_avatar!(id)

    if avatar.visibility == "public" do
      conn
      |> json(%{
        avatarId: avatar.id,
        publicUrl: url(conn, ~p"/avatars/#{avatar.id}"),
        configUrl: url(conn, ~p"/api/avatars/#{avatar.id}/config"),
        embedUrl: url(conn, ~p"/avatars/#{avatar.id}"),
        visibility: avatar.visibility,
        updatedAt: avatar.updated_at
      })
    else
      send_resp(conn, :not_found, "avatar is private")
    end
  end

  defp serialize(avatar) do
    %{
      id: avatar.id,
      name: avatar.name,
      config: avatar.config,
      visibility: avatar.visibility,
      insertedAt: avatar.inserted_at,
      updatedAt: avatar.updated_at
    }
  end
end
