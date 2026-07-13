defmodule Oneme.Generations.GenerationJob do
  use Ecto.Schema
  import Ecto.Changeset

  schema "generation_jobs" do
    field :kind, :string
    field :input_config, :map
    field :status, :string, default: "queued"
    field :candidates, :map, default: %{}
    field :attempts, :integer, default: 0
    field :error_code, :string
    field :error_message, :string
    field :finished_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :kind,
      :input_config,
      :status,
      :candidates,
      :attempts,
      :error_code,
      :error_message,
      :finished_at
    ])
    |> validate_required([:kind, :input_config, :status, :candidates])
    |> validate_inclusion(:kind, ["face_candidates"])
    |> validate_inclusion(:status, ~w(queued running succeeded failed))
  end
end
