defmodule Oneme.FaceAnalyses.FaceAnalysisJob do
  use Ecto.Schema
  import Ecto.Changeset

  schema "face_analysis_jobs" do
    field :status, :string, default: "queued"
    field :input_metadata, :map, default: %{}
    field :result, :map, default: %{}
    field :attempts, :integer, default: 0
    field :error_code, :string
    field :error_message, :string
    field :expires_at, :utc_datetime
    field :consumed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :status,
      :input_metadata,
      :result,
      :attempts,
      :error_code,
      :error_message,
      :expires_at,
      :consumed_at
    ])
    |> validate_required([:status, :input_metadata, :result, :attempts, :expires_at])
    |> validate_inclusion(:status, ~w(queued running succeeded failed expired))
  end
end
