defmodule Oneme.Webhooks.WebhookEndpoint do
  use Ecto.Schema
  import Ecto.Changeset

  schema "webhook_endpoints" do
    field :team_id, :id
    field :name, :string
    field :url, :string
    field :events, {:array, :string}, default: []
    field :secret_prefix, :string
    field :secret_ciphertext, :string
    field :active, :boolean, default: true
    field :last_delivered_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(endpoint, attrs) do
    endpoint
    |> cast(attrs, [
      :team_id,
      :name,
      :url,
      :events,
      :secret_prefix,
      :secret_ciphertext,
      :active,
      :last_delivered_at
    ])
    |> validate_required([
      :team_id,
      :name,
      :url,
      :events,
      :secret_prefix,
      :secret_ciphertext,
      :active
    ])
    |> validate_format(:url, ~r/^https?:\/\//)
  end
end
