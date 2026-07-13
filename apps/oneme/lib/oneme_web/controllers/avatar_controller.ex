defmodule OnemeWeb.AvatarController do
  use OnemeWeb, :controller

  alias Oneme.Avatars
  alias Oneme.Operations

  def create(conn, params) do
    attrs = %{
      name: Map.get(params, "name", Map.get(params, "avatarName", "My oneme avatar")),
      config: Map.get(params, "config", %{}),
      visibility: Map.get(params, "visibility", "private")
    }

    case Avatars.create_avatar(attrs) do
      {:ok, avatar} ->
        conn |> put_status(:created) |> json(serialize(avatar))

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(changeset.errors)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    avatar = Avatars.get_avatar!(id)

    attrs =
      params
      |> Map.take(["name", "avatarName", "config", "visibility"])
      |> normalize_update_attrs()

    case Avatars.update_avatar(avatar, attrs) do
      {:ok, updated_avatar} ->
        conn |> json(serialize(updated_avatar))

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(changeset.errors)})
    end
  end

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
      Operations.track_usage("public_avatar_read", %{
        subject_type: "avatar",
        subject_id: avatar.id
      })

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

  defp normalize_update_attrs(attrs) do
    case Map.pop(attrs, "avatarName") do
      {nil, attrs} -> attrs
      {name, attrs} -> Map.put(attrs, "name", name)
    end
  end
end
