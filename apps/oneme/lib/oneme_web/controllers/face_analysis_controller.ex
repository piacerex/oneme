defmodule OnemeWeb.FaceAnalysisController do
  use OnemeWeb, :controller

  alias Oneme.Avatars
  alias Oneme.FaceAnalyses
  alias OnemeWeb.Authorization

  def create(conn, params) do
    case authorize(conn, "editor") do
      :ok ->
        case FaceAnalyses.create_job(params) do
          {:ok, job} ->
            conn |> put_status(:accepted) |> json(serialize(job))

          {:error, changeset} ->
            conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(changeset.errors)})
        end

      {:error, :forbidden} ->
        forbidden(conn)
    end
  end

  def show(conn, %{"id" => id}) do
    case authorize(conn, "viewer") do
      :ok -> json(conn, serialize(FaceAnalyses.get_job!(id)))
      {:error, :forbidden} -> forbidden(conn)
    end
  end

  def create_avatar(conn, params) do
    with :ok <- authorize(conn, "editor"),
         job <- FaceAnalyses.get_job!(Map.get(params, "faceAnalysisJobId")),
         {:ok, attrs} <- FaceAnalyses.create_avatar_attrs(job, params),
         attrs <- Map.put(attrs, :team_id, team_id(conn)),
         {:ok, avatar} <- Avatars.create_avatar(attrs) do
      conn
      |> put_status(:created)
      |> json(%{avatarId: avatar.id, name: avatar.name, config: avatar.config})
    else
      {:error, :forbidden} ->
        forbidden(conn)

      {:error, :analysis_unavailable} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "analysis_unavailable"})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(changeset.errors)})
    end
  end

  defp serialize(job) do
    %{
      id: job.id,
      status: job.status,
      result: job.result,
      attempts: job.attempts,
      errorCode: job.error_code,
      errorMessage: job.error_message,
      expiresAt: job.expires_at,
      consumedAt: job.consumed_at,
      createdAt: job.inserted_at
    }
  end

  defp authorize(conn, role) do
    if Authorization.allowed?(conn, role), do: :ok, else: {:error, :forbidden}
  end

  defp team_id(%{assigns: %{principal: %{team_id: team_id}}}), do: team_id
  defp team_id(_conn), do: nil

  defp forbidden(conn), do: conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
end
