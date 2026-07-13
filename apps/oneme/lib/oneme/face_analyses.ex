defmodule Oneme.FaceAnalyses do
  @moduledoc "Short-lived face analysis metadata jobs without source image storage."

  alias Oneme.FaceAnalyses.FaceAnalysisJob
  alias Oneme.Operations
  alias Oneme.Repo

  @ttl_seconds 900

  def create_job(attrs) when is_map(attrs) do
    metadata = sanitize_metadata(Map.get(attrs, "analysis", Map.get(attrs, :analysis, %{})))

    expires_at =
      DateTime.utc_now() |> DateTime.add(@ttl_seconds, :second) |> DateTime.truncate(:second)

    job_attrs = %{
      status: "queued",
      input_metadata: metadata,
      result: %{},
      attempts: 0,
      expires_at: expires_at
    }

    with {:ok, job} <- %FaceAnalysisJob{} |> FaceAnalysisJob.changeset(job_attrs) |> Repo.insert() do
      Operations.track_usage("face_analysis_requested", %{
        subject_type: "face_analysis_job",
        subject_id: job.id
      })

      {:ok, execute(job)}
    end
  end

  def create_job(_attrs), do: {:error, :invalid_metadata}

  def get_job!(id), do: Repo.get!(FaceAnalysisJob, id) |> expire_if_needed()

  def create_avatar_attrs(%FaceAnalysisJob{} = job, attrs) do
    job = expire_if_needed(job)

    if job.status != "succeeded" do
      {:error, :analysis_unavailable}
    else
      config = Map.get(attrs, "avatarConfig", Map.get(attrs, :avatar_config, %{}))
      config = if is_map(config), do: config, else: %{}
      result = job.result

      {:ok,
       %{
         name: Map.get(attrs, "name", Map.get(attrs, :name, "Face analysis avatar")),
         visibility: Map.get(attrs, "visibility", Map.get(attrs, :visibility, "private")),
         config:
           config
           |> Map.put(
             "colors",
             Map.merge(Map.get(config, "colors", %{}), Map.get(result, "colors", %{}))
           )
           |> Map.put(
             "faceMorph",
             Map.merge(Map.get(config, "faceMorph", %{}), Map.get(result, "faceMorph", %{}))
           )
           |> Map.put("faceAnalysis", Map.drop(result, ["faceMorph", "colors"]))
       }}
    end
  end

  defp execute(job) do
    {:ok, running_job} =
      job
      |> FaceAnalysisJob.changeset(%{status: "running", attempts: job.attempts + 1})
      |> Repo.update()

    result = %{
      "detected" => Map.get(job.input_metadata, "detected", false),
      "colors" => Map.get(job.input_metadata, "colors", %{}),
      "faceMorph" => Map.get(job.input_metadata, "faceMorph", %{})
    }

    {:ok, finished_job} =
      running_job
      |> FaceAnalysisJob.changeset(%{status: "succeeded", result: result})
      |> Repo.update()

    Operations.track_audit("face_analysis_succeeded", %{
      resource_type: "face_analysis_job",
      resource_id: finished_job.id,
      metadata: %{"detected" => result["detected"]}
    })

    finished_job
  rescue
    error ->
      {:ok, failed_job} =
        job
        |> FaceAnalysisJob.changeset(%{
          status: "failed",
          attempts: job.attempts + 1,
          error_code: "face_analysis_failed",
          error_message: Exception.message(error)
        })
        |> Repo.update()

      Operations.track_audit("face_analysis_failed", %{
        resource_type: "face_analysis_job",
        resource_id: failed_job.id,
        metadata: %{"errorCode" => failed_job.error_code}
      })

      failed_job
  end

  defp expire_if_needed(%FaceAnalysisJob{status: "succeeded", expires_at: expires_at} = job) do
    if DateTime.compare(DateTime.utc_now(), expires_at) == :gt do
      {:ok, expired} =
        job
        |> FaceAnalysisJob.changeset(%{status: "expired", result: %{}})
        |> Repo.update()

      expired
    else
      job
    end
  end

  defp expire_if_needed(job), do: job

  defp sanitize_metadata(metadata) when is_map(metadata) do
    %{
      "detected" => Map.get(metadata, "detected", false) in [true, "true"],
      "colors" => sanitize_colors(Map.get(metadata, "colors", %{})),
      "faceMorph" => sanitize_morph(Map.get(metadata, "faceMorph", %{}))
    }
  end

  defp sanitize_metadata(_metadata),
    do: %{"detected" => false, "colors" => %{}, "faceMorph" => %{}}

  defp sanitize_colors(colors) when is_map(colors) do
    colors
    |> Map.take(["skin", "hair"])
    |> Map.new(fn {key, value} -> {key, value} end)
  end

  defp sanitize_colors(_colors), do: %{}

  defp sanitize_morph(morph) when is_map(morph),
    do: Map.take(morph, ["widthScale", "heightScale", "depth"])

  defp sanitize_morph(_morph), do: %{}
end
