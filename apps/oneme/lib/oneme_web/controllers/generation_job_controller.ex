defmodule OnemeWeb.GenerationJobController do
  use OnemeWeb, :controller

  alias Oneme.Billing
  alias Oneme.Generations
  alias OnemeWeb.Authorization

  def create(conn, params) do
    with :ok <- authorize(conn, "editor"),
         :ok <- authorize_generation(conn),
         {:ok, job} <- Generations.create_candidate_job(Map.get(params, "avatarConfig", %{})) do
      conn |> put_status(:created) |> json(serialize(job))
    else
      {:error, :forbidden} ->
        forbidden(conn)

      {:error, :quota_exceeded} ->
        conn |> put_status(:too_many_requests) |> json(%{error: "generation_quota_exceeded"})

      {:error, :subscription_inactive} ->
        conn |> put_status(:payment_required) |> json(%{error: "subscription_inactive"})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(changeset.errors)})
    end
  end

  def show(conn, %{"id" => id}) do
    case authorize(conn, "viewer") do
      :ok -> json(conn, serialize(Generations.get_generation_job!(id)))
      {:error, :forbidden} -> forbidden(conn)
    end
  end

  def feedback(conn, %{"id" => id} = params) do
    with :ok <- authorize(conn, "editor"),
         job <- Generations.get_generation_job!(id),
         {:ok, updated_job} <-
           Generations.feedback(job, Map.get(params, "candidateId"), Map.get(params, "decision")) do
      conn |> json(serialize(updated_job))
    else
      {:error, :forbidden} ->
        forbidden(conn)

      {:error, reason}
      when reason in [:invalid_decision, :invalid_feedback, :candidate_not_found] ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: Atom.to_string(reason)})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(changeset.errors)})
    end
  end

  def retry(conn, %{"id" => id}) do
    with :ok <- authorize(conn, "editor"),
         :ok <- authorize_generation(conn),
         job <- Generations.get_generation_job!(id),
         {:ok, retried_job} <- Generations.retry_candidate_job(job) do
      conn |> put_status(:accepted) |> json(serialize(retried_job))
    else
      {:error, :forbidden} ->
        forbidden(conn)

      {:error, :job_not_retryable} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "job_not_retryable"})

      {:error, :quota_exceeded} ->
        conn |> put_status(:too_many_requests) |> json(%{error: "generation_quota_exceeded"})

      {:error, :subscription_inactive} ->
        conn |> put_status(:payment_required) |> json(%{error: "subscription_inactive"})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(changeset.errors)})
    end
  end

  def regenerate(conn, %{"id" => id}) do
    with :ok <- authorize(conn, "editor"),
         :ok <- authorize_generation(conn),
         job <- Generations.get_generation_job!(id),
         {:ok, regenerated_job} <- Generations.regenerate_candidate_job(job) do
      conn |> put_status(:accepted) |> json(serialize(regenerated_job))
    else
      {:error, :forbidden} ->
        forbidden(conn)

      {:error, :quota_exceeded} ->
        conn |> put_status(:too_many_requests) |> json(%{error: "generation_quota_exceeded"})

      {:error, :subscription_inactive} ->
        conn |> put_status(:payment_required) |> json(%{error: "subscription_inactive"})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(changeset.errors)})
    end
  end

  defp authorize(conn, role) do
    if Authorization.allowed?(conn, role), do: :ok, else: {:error, :forbidden}
  end

  defp authorize_generation(conn) do
    case conn.assigns[:principal] do
      %{team_id: team_id} -> Billing.authorize_usage(team_id, "generation_requested")
      _ -> :ok
    end
  end

  defp forbidden(conn), do: conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

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
