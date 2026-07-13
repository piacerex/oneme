defmodule Oneme.Repo.Migrations.CreateWebhooks do
  use Ecto.Migration

  def change do
    create table(:webhook_endpoints) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :url, :string, null: false
      add :events, {:array, :string}, null: false, default: []
      add :secret_prefix, :string, null: false
      add :secret_ciphertext, :text, null: false
      add :active, :boolean, null: false, default: true
      add :last_delivered_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:webhook_endpoints, [:team_id, :active])

    create table(:webhook_deliveries) do
      add :webhook_endpoint_id, references(:webhook_endpoints, on_delete: :delete_all),
        null: false

      add :event_type, :string, null: false
      add :event_id, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :status, :string, null: false, default: "queued"
      add :attempts, :integer, null: false, default: 0
      add :response_status, :integer
      add :signature, :string, null: false
      add :error_message, :text
      add :delivered_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:webhook_deliveries, [:webhook_endpoint_id, :inserted_at])
    create index(:webhook_deliveries, [:event_type, :status])
  end
end
