defmodule OnemeWeb.AvatarController do
  use OnemeWeb, :controller

  alias Oneme.Avatars
  alias Oneme.Exports
  alias Oneme.Operations
  alias OnemeWeb.Authorization

  def create(conn, params) do
    attrs = %{
      name: Map.get(params, "name", Map.get(params, "avatarName", "My oneme avatar")),
      config: Map.get(params, "config", %{}),
      visibility: Map.get(params, "visibility", "private"),
      team_id: team_id(conn)
    }

    case authorize(conn, "editor") do
      :ok -> create_avatar(conn, attrs)
      {:error, :forbidden} -> forbidden(conn)
    end
  end

  defp create_avatar(conn, attrs) do
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

    case authorize_avatar(conn, avatar, "editor") do
      :ok -> update_avatar(conn, avatar, attrs)
      {:error, :forbidden} -> forbidden(conn)
    end
  end

  defp update_avatar(conn, avatar, attrs) do
    case Avatars.update_avatar(avatar, attrs) do
      {:ok, updated_avatar} ->
        conn |> json(serialize(updated_avatar))

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(changeset.errors)})
    end
  end

  def show(conn, %{"id" => id}) do
    avatar = Avatars.get_avatar!(id)

    case authorize_avatar(conn, avatar, "viewer") do
      :ok -> json(conn, serialize(avatar))
      {:error, :forbidden} -> forbidden(conn)
    end
  end

  def config(conn, %{"id" => id}) do
    avatar = Avatars.get_avatar!(id)

    case authorize_avatar(conn, avatar, "viewer") do
      :ok ->
        json(conn, %{avatarId: avatar.id, config: avatar.config, updatedAt: avatar.updated_at})

      {:error, :forbidden} ->
        forbidden(conn)
    end
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

  def export(conn, %{"id" => id} = params) do
    avatar = Avatars.get_avatar!(id)

    with :ok <- ensure_public(avatar),
         {:ok, job} <- create_avatar_export(avatar, params) do
      conn |> put_status(:created) |> json(serialize_export(job, avatar.id))
    else
      {:error, :private_avatar} ->
        send_resp(conn, :not_found, "avatar is private")

      {:error, :unsupported_format} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "unsupported_format"})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(changeset.errors)})
    end
  end

  def model(conn, %{"id" => id} = params) do
    avatar = Avatars.get_avatar!(id)

    with :ok <- ensure_public(avatar),
         {:ok, job} <- create_avatar_export(avatar, params) do
      conn |> json(serialize_export(job, avatar.id))
    else
      {:error, :private_avatar} ->
        send_resp(conn, :not_found, "avatar is private")

      {:error, :unsupported_format} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "unsupported_format"})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(changeset.errors)})
    end
  end

  defp serialize(avatar) do
    %{
      id: avatar.id,
      name: avatar.name,
      config: avatar.config,
      visibility: avatar.visibility,
      teamId: avatar.team_id,
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

  defp ensure_public(%{visibility: "public"}), do: :ok
  defp ensure_public(_avatar), do: {:error, :private_avatar}

  defp authorize(conn, role) do
    if Authorization.allowed?(conn, role), do: :ok, else: {:error, :forbidden}
  end

  defp authorize_avatar(_conn, %{visibility: "public"}, "viewer"), do: :ok

  defp authorize_avatar(conn, avatar, role) do
    if authorize(conn, role) == :ok and Authorization.team_matches?(conn, avatar.team_id),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp team_id(%{assigns: %{principal: %{team_id: team_id}}}), do: team_id
  defp team_id(_conn), do: nil

  defp forbidden(conn) do
    conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
  end

  defp create_avatar_export(avatar, params) do
    Exports.create_export_job(%{
      avatar_config: Map.get(params, "avatarConfig", avatar.config),
      format: Map.get(params, "format", "glb"),
      face_texture_data_url: Map.get(params, "faceTextureDataUrl")
    })
  end

  defp serialize_export(job, avatar_id) do
    %{
      avatarId: avatar_id,
      exportJobId: job.id,
      format: job.format,
      status: job.status,
      modelUrl: job.model_path,
      cacheKey: job.cache_key,
      cacheHit: job.cache_hit,
      includesFaceTexture: job.includes_face_texture,
      errorCode: job.error_code,
      errorMessage: job.error_message,
      createdAt: job.inserted_at,
      finishedAt: job.finished_at
    }
  end
end
