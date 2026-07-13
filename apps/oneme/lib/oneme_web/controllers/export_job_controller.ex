defmodule OnemeWeb.ExportJobController do
  use OnemeWeb, :controller

  alias Oneme.Exports

  def create(conn, params) do
    attrs = %{
      avatar_config: Map.get(params, "avatarConfig", %{}),
      format: Map.get(params, "format", "glb"),
      face_texture_data_url: Map.get(params, "faceTextureDataUrl")
    }

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
    conn |> json(serialize(Exports.get_export_job!(id)))
  end

  defp serialize(job) do
    %{
      id: job.id,
      format: job.format,
      status: job.status,
      cacheKey: job.cache_key,
      modelUrl: job.model_path,
      includesFaceTexture: job.includes_face_texture,
      errorCode: job.error_code,
      errorMessage: job.error_message,
      createdAt: job.inserted_at,
      finishedAt: job.finished_at
    }
  end
end
