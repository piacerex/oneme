defmodule Oneme.Billing.BillingEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "billing_events" do
    field :team_id, :id
    field :provider, :string
    field :external_id, :string
    field :event_type, :string
    field :payload, :map, default: %{}
    field :processed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:team_id, :provider, :external_id, :event_type, :payload, :processed_at])
    |> validate_required([:provider, :external_id, :event_type, :payload])
    |> unique_constraint([:provider, :external_id])
  end
end
