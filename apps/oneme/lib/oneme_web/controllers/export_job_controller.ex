defmodule OnemeWeb.ExportJobController do
  use OnemeWeb, :controller

  alias Oneme.Exports
  alias OnemeWeb.Authorization

  def create(conn, params) do
    attrs = %{
      avatar_config: Map.get(params, "avatarConfig", %{}),
      format: Map.get(params, "format", "glb"),
      face_texture_data_url: Map.get(params, "faceTextureDataUrl")
    }

    case authorize(conn, "editor") do
      :ok -> create_job(conn, attrs)
      {:error, :forbidden} -> forbidden(conn)
    end
  end

  defp create_job(conn, attrs) do
    case Exports.create_export_job(attrs) do
      {:ok, job} ->
        conn |> put_status(:created) |> json(serialize(job))

      {:error, :unsupported_format} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "unsupported_format"})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(changeset.errors)})
    end
  end

  def show(conn, %{"id" => id}) do
    case authorize(conn, "viewer") do
      :ok -> json(conn, serialize(Exports.get_export_job!(id)))
      {:error, :forbidden} -> forbidden(conn)
    end
  end

  def retry(conn, %{"id" => id}) do
    case authorize(conn, "editor") do
      :ok -> retry_job(conn, Exports.get_export_job!(id))
      {:error, :forbidden} -> forbidden(conn)
    end
  end

  defp retry_job(conn, job) do
    case Exports.retry_export_job(job) do
      {:ok, job} ->
        conn |> put_status(:accepted) |> json(serialize(job))

      {:error, :face_texture_retry_requires_source} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "face_texture_retry_requires_source"})

      {:error, :unsupported_format} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "unsupported_format"})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(changeset.errors)})
    end
  end

  defp authorize(conn, role) do
    if Authorization.allowed?(conn, role), do: :ok, else: {:error, :forbidden}
  end

  defp forbidden(conn), do: conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

  defp serialize(job) do
    %{
      id: job.id,
      format: job.format,
      status: job.status,
      cacheKey: job.cache_key,
      cacheHit: job.cache_hit,
      modelUrl: job.model_path,
      includesFaceTexture: job.includes_face_texture,
      errorCode: job.error_code,
      errorMessage: job.error_message,
      createdAt: job.inserted_at,
      finishedAt: job.finished_at
    }
  end
end
