defmodule Oneme.Monitoring.ProbeRun do
  use Ecto.Schema
  import Ecto.Changeset

  schema "monitoring_probe_runs" do
    field :status, :string
    field :endpoint_count, :integer, default: 0
    field :available_count, :integer, default: 0
    field :availability_percent, :float
    field :report, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def changeset(probe_run, attrs) do
    probe_run
    |> cast(attrs, [
      :status,
      :endpoint_count,
      :available_count,
      :availability_percent,
      :report
    ])
    |> validate_required([:status, :endpoint_count, :available_count, :report])
    |> validate_number(:endpoint_count, greater_than_or_equal_to: 0)
    |> validate_number(:available_count, greater_than_or_equal_to: 0)
    |> validate_number(:availability_percent,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100
    )
  end
end
