defmodule Oneme.Webhooks.WebhookDelivery do
  use Ecto.Schema
  import Ecto.Changeset

  schema "webhook_deliveries" do
    field :webhook_endpoint_id, :id
    field :event_type, :string
    field :event_id, :string
    field :payload, :map, default: %{}
    field :status, :string, default: "queued"
    field :attempts, :integer, default: 0
    field :response_status, :integer
    field :signature, :string
    field :error_message, :string
    field :delivered_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [
      :webhook_endpoint_id,
      :event_type,
      :event_id,
      :payload,
      :status,
      :attempts,
      :response_status,
      :signature,
      :error_message,
      :delivered_at
    ])
    |> validate_required([
      :webhook_endpoint_id,
      :event_type,
      :event_id,
      :payload,
      :status,
      :signature
    ])
    |> validate_inclusion(:status, ~w(queued delivering succeeded failed))
  end
end
