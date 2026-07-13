defmodule OnemeWeb.AvatarController do
  use OnemeWeb, :controller

  alias Oneme.Avatars
  alias Oneme.Exports
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
