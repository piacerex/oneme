defmodule Oneme.Generations do
  @moduledoc "Provider-neutral candidate generation jobs for avatar recommendations."

  alias Oneme.Generations.GenerationJob
  alias Oneme.Generations.ExternalProvider
  alias Oneme.Operations
  alias Oneme.Repo

  @presets [
    %{
      "id" => "candidate-soft",
      "label" => "Soft Studio",
      "style" => "soft",
      "reason" => "やわらかな顔立ちに合わせた自然な組み合わせです。",
      "parts" => %{
        "face" => "face.soft_01",
        "hair" => "hair.short_01",
        "top" => "top.basic_01",
        "bottom" => "bottom.basic_01",
        "accessory" => "accessory.none"
      }
    },
    %{
      "id" => "candidate-studio",
      "label" => "Studio Edge",
      "style" => "studio",
      "reason" => "輪郭を引き締めて、撮影向けの印象に寄せます。",
      "parts" => %{
        "face" => "face.sharp_01",
        "hair" => "hair.bob_01",
        "top" => "top.jacket_01",
        "bottom" => "bottom.tapered_01",
        "accessory" => "accessory.glasses_01"
      }
    },
    %{
      "id" => "candidate-expressive",
      "label" => "Expressive Color",
      "style" => "expressive",
      "reason" => "髪型と色の差を出した、表情の見えやすい組み合わせです。",
      "parts" => %{
        "face" => "face.round_01",
        "hair" => "hair.long_01",
        "top" => "top.hoodie_01",
        "bottom" => "bottom.skirt_01",
        "accessory" => "accessory.none"
      }
    }
  ]

  def get_generation_job!(id), do: Repo.get!(GenerationJob, id)

  def create_candidate_job(config) when is_map(config) do
    input_config = sanitize_config(config)

    attrs = %{
      kind: "face_candidates",
      input_config: input_config,
      status: "queued",
      candidates: %{},
      attempts: 0
    }

    with {:ok, job} <- %GenerationJob{} |> GenerationJob.changeset(attrs) |> Repo.insert() do
      Operations.track_usage("generation_requested", %{
        subject_type: "generation_job",
        subject_id: job.id,
        metadata: %{"kind" => job.kind}
      })

      {:ok, execute(job)}
    end
  end

  def create_candidate_job(_config), do: {:error, :invalid_config}

  def retry_candidate_job(%GenerationJob{status: "failed"} = job) do
    with {:ok, queued_job} <-
           job
           |> GenerationJob.changeset(%{
             status: "queued",
             candidates: %{},
             error_code: nil,
             error_message: nil,
             finished_at: nil
           })
           |> Repo.update() do
      {:ok, execute(queued_job)}
    end
  end

  def retry_candidate_job(%GenerationJob{}), do: {:error, :job_not_retryable}

  def regenerate_candidate_job(%GenerationJob{} = job), do: create_candidate_job(job.input_config)

  def feedback(%GenerationJob{} = job, candidate_id, decision)
      when is_binary(candidate_id) and is_binary(decision) do
    with true <- decision in ["adopt", "reject"],
         {:ok, candidates} <- update_candidate(job.candidates, candidate_id, decision),
         {:ok, updated_job} <-
           job
           |> GenerationJob.changeset(%{candidates: candidates})
           |> Repo.update() do
      Operations.track_usage("generation_feedback", %{
        subject_type: "generation_job",
        subject_id: job.id,
        metadata: %{"candidateId" => candidate_id, "decision" => decision}
      })

      Operations.track_audit("generation_#{decision}", %{
        resource_type: "generation_job",
        resource_id: job.id,
        metadata: %{"candidateId" => candidate_id}
      })

      {:ok, updated_job}
    else
      false -> {:error, :invalid_decision}
      {:error, :candidate_not_found} -> {:error, :candidate_not_found}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def feedback(_job, _candidate_id, _decision), do: {:error, :invalid_feedback}

  def candidate_items(%GenerationJob{candidates: candidates}),
    do: Map.get(candidates || %{}, "items", [])

  defp execute(job) do
    {:ok, running_job} =
      job
      |> GenerationJob.changeset(%{status: "running", attempts: job.attempts + 1})
      |> Repo.update()

    {provider, candidates} = generate_candidates(running_job.input_config)
    finished_at = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, finished_job} =
      running_job
      |> GenerationJob.changeset(%{
        status: "succeeded",
        candidates: %{"items" => candidates, "provider" => provider},
        finished_at: finished_at
      })
      |> Repo.update()

    Operations.track_audit("generation_succeeded", %{
      resource_type: "generation_job",
      resource_id: finished_job.id,
      metadata: %{"candidateCount" => length(candidates), "provider" => provider}
    })

    finished_job
  rescue
    error ->
      {:ok, failed_job} =
        job
        |> GenerationJob.changeset(%{
          status: "failed",
          error_code: "candidate_generation_failed",
          error_message: Exception.message(error),
          finished_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update()

      Operations.track_audit("generation_failed", %{
        resource_type: "generation_job",
        resource_id: failed_job.id,
        metadata: %{"errorCode" => failed_job.error_code}
      })

      failed_job
  end

  defp build_candidate(preset, input_config) do
    config =
      input_config
      |> Map.put("parts", Map.merge(Map.get(input_config, "parts", %{}), preset["parts"]))

    Map.merge(preset, %{"status" => "available", "config" => config})
  end

  defp generate_candidates(input_config) do
    case System.get_env("ONEME_GENERATION_PROVIDER", "local_recommendation") do
      "local_recommendation" ->
        {"local_recommendation", Enum.map(@presets, &build_candidate(&1, input_config))}

      "http_json" ->
        case ExternalProvider.generate(input_config) do
          {:ok, %{provider: provider, candidates: candidates}} ->
            {provider, normalize_external_candidates(candidates, input_config)}

          {:error, code, message} ->
            raise "#{code}: #{message}"

          {:error, reason} ->
            raise "external provider failed: #{inspect(reason)}"
        end

      provider ->
        raise "unsupported generation provider: #{provider}"
    end
  end

  defp normalize_external_candidates(candidates, input_config) do
    candidates
    |> Enum.with_index(1)
    |> Enum.map(fn {candidate, index} ->
      normalize_external_candidate(candidate, input_config, index)
    end)
  end

  defp normalize_external_candidate(candidate, input_config, index) when is_map(candidate) do
    parts =
      candidate
      |> map_value("parts")
      |> Map.take(~w(face hair top bottom accessory))

    config = Map.put(input_config, "parts", Map.merge(Map.get(input_config, "parts", %{}), parts))

    normalized = %{
      "id" => safe_text(candidate, "id", "external-#{index}"),
      "label" => safe_text(candidate, "label", "External candidate #{index}"),
      "style" => safe_text(candidate, "style", "external"),
      "reason" => safe_text(candidate, "reason", "外部プロバイダーが生成した候補です。"),
      "parts" => parts,
      "status" => "available",
      "config" => config
    }

    case candidate |> Map.get("imageUrl") |> valid_image_url() do
      nil -> normalized
      image_url -> Map.put(normalized, "imageUrl", image_url)
    end
  end

  defp normalize_external_candidate(_candidate, input_config, index),
    do: normalize_external_candidate(%{}, input_config, index)

  defp safe_text(candidate, key, fallback) do
    case Map.get(candidate, key) do
      value when is_binary(value) and value != "" -> String.slice(value, 0, 240)
      _ -> fallback
    end
  end

  defp valid_image_url(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: "https", host: host} when is_binary(host) -> String.slice(value, 0, 2_000)
      _ -> nil
    end
  end

  defp valid_image_url(_value), do: nil

  defp update_candidate(candidates, candidate_id, decision) do
    items = Map.get(candidates || %{}, "items", [])

    if Enum.any?(items, &(&1["id"] == candidate_id)) do
      next_items =
        Enum.map(items, fn candidate ->
          if candidate["id"] == candidate_id do
            Map.put(candidate, "status", if(decision == "adopt", do: "adopted", else: "rejected"))
          else
            candidate
          end
        end)

      selected_id =
        if decision == "adopt", do: candidate_id, else: Map.get(candidates, "selectedId")

      next = Map.put(candidates, "items", next_items)
      next = if selected_id, do: Map.put(next, "selectedId", selected_id), else: next
      {:ok, next}
    else
      {:error, :candidate_not_found}
    end
  end

  defp sanitize_config(config) do
    parts = map_value(config, "parts")
    colors = map_value(config, "colors")
    face_morph = map_value(config, "faceMorph")
    face_analysis = config |> map_value("faceAnalysis") |> Map.take(["detected"])

    face_texture =
      config |> map_value("faceTexture") |> Map.take(["enabled", "source", "exportConsent"])

    %{
      "parts" => parts,
      "colors" => colors,
      "faceMorph" => face_morph,
      "faceAnalysis" => face_analysis,
      "faceTexture" => face_texture
    }
  end

  defp map_value(config, key) do
    case Map.get(config, key, %{}) do
      value when is_map(value) -> value
      _ -> %{}
    end
  end
end
