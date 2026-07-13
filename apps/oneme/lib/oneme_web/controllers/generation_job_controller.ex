defmodule OnemeWeb.GenerationJobController do
  use OnemeWeb, :controller

  alias Oneme.Generations

  def create(conn, params) do
    case Generations.create_candidate_job(Map.get(params, "avatarConfig", %{})) do
      {:ok, job} ->
        conn |> put_status(:created) |> json(serialize(job))

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(changeset.errors)})
    end
  end

  def show(conn, %{"id" => id}) do
    conn |> json(serialize(Generations.get_generation_job!(id)))
  end

  def feedback(conn, %{"id" => id} = params) do
    job = Generations.get_generation_job!(id)

    case Generations.feedback(job, Map.get(params, "candidateId"), Map.get(params, "decision")) do
      {:ok, updated_job} ->
        conn |> json(serialize(updated_job))

      {:error, reason}
      when reason in [:invalid_decision, :invalid_feedback, :candidate_not_found] ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: Atom.to_string(reason)})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(changeset.errors)})
    end
  end

  defp serialize(job) do
    %{
      id: job.id,
      kind: job.kind,
      status: job.status,
      candidates: Generations.candidate_items(job),
      provider: Map.get(job.candidates || %{}, "provider"),
      attempts: job.attempts,
      errorCode: job.error_code,
      errorMessage: job.error_message,
      createdAt: job.inserted_at,
      finishedAt: job.finished_at
    }
  end
end
