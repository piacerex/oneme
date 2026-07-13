defmodule Oneme.Usage.UsageCounter do
  use Ecto.Schema
  import Ecto.Changeset

  schema "usage_counters" do
    field :team_id, :id
    field :period_start, :date
    field :metric, :string
    field :quantity, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def changeset(counter, attrs) do
    counter
    |> cast(attrs, [:team_id, :period_start, :metric, :quantity])
    |> validate_required([:team_id, :period_start, :metric, :quantity])
    |> validate_number(:quantity, greater_than_or_equal_to: 0)
    |> unique_constraint([:team_id, :period_start, :metric])
  end
end
