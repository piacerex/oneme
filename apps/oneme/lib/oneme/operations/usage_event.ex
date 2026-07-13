defmodule Oneme.Operations.UsageEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "usage_events" do
    field :event_type, :string
    field :subject_type, :string
    field :subject_id, :string
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:event_type, :subject_type, :subject_id, :metadata])
    |> validate_required([:event_type, :metadata])
  end
end
