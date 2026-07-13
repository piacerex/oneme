defmodule Oneme.GenerationsTest do
  use Oneme.DataCase

  alias Oneme.Generations
  alias Oneme.Generations.GenerationJob
  alias Oneme.Repo

  test "creates three candidates without storing a face image" do
    config = %{
      "parts" => %{"top" => "top.basic_01"},
      "faceMorph" => %{"widthScale" => 1.08},
      "faceTexture" => %{"enabled" => true, "exportConsent" => false},
      "faceImageDataUrl" => "data:image/png;base64,should-not-persist"
    }

    assert {:ok, job} = Generations.create_candidate_job(config)
    assert job.status == "succeeded"
    assert length(Generations.candidate_items(job)) == 3
    assert job.input_config["faceTexture"] == %{"enabled" => true, "exportConsent" => false}
    refute Jason.encode!(job.input_config) =~ "should-not-persist"
  end

  test "records candidate adoption and rejection" do
    assert {:ok, job} = Generations.create_candidate_job(%{})
    [first | rest] = Generations.candidate_items(job)

    assert {:ok, adopted} = Generations.feedback(job, first["id"], "adopt")

    adopted_candidate =
      Enum.find(Generations.candidate_items(adopted), &(&1["id"] == first["id"]))

    assert adopted_candidate["status"] == "adopted"

    second = hd(rest)
    assert {:ok, rejected} = Generations.feedback(adopted, second["id"], "reject")

    rejected_candidate =
      Enum.find(Generations.candidate_items(rejected), &(&1["id"] == second["id"]))

    assert rejected_candidate["status"] == "rejected"
  end

  test "rejects unknown candidate ids" do
    assert {:ok, job} = Generations.create_candidate_job(%{})
    assert {:error, :candidate_not_found} = Generations.feedback(job, "unknown", "reject")
    assert %GenerationJob{} = Generations.get_generation_job!(job.id)
  end

  test "regenerates a completed job with a new job id" do
    assert {:ok, job} = Generations.create_candidate_job(%{})
    assert {:ok, regenerated} = Generations.regenerate_candidate_job(job)
    assert regenerated.id != job.id
    assert regenerated.status == "succeeded"
    assert length(Generations.candidate_items(regenerated)) == 3
  end

  test "retries a failed job" do
    assert {:ok, job} = Generations.create_candidate_job(%{})

    {:ok, failed_job} =
      job
      |> GenerationJob.changeset(%{
        status: "failed",
        error_code: "temporary",
        error_message: "retry me"
      })
      |> Repo.update()

    assert {:ok, retried} = Generations.retry_candidate_job(failed_job)
    assert retried.status == "succeeded"
    assert retried.attempts == failed_job.attempts + 1
  end
end
