defmodule Oneme.Repo.Migrations.CreateOperationsEvents do
  use Ecto.Migration

  def change do
    create table(:usage_events) do
      add :event_type, :string, null: false
      add :subject_type, :string
      add :subject_id, :string
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:usage_events, [:event_type, :inserted_at])
    create index(:usage_events, [:subject_type, :subject_id])

    create table(:audit_logs) do
      add :action, :string, null: false
      add :resource_type, :string
      add :resource_id, :string
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:audit_logs, [:action, :inserted_at])
    create index(:audit_logs, [:resource_type, :resource_id])
  end
end
