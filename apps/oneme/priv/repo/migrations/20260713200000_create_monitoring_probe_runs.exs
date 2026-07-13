defmodule Oneme.Repo.Migrations.CreateMonitoringProbeRuns do
  use Ecto.Migration

  def change do
    create table(:monitoring_probe_runs) do
      add :status, :string, null: false
      add :endpoint_count, :integer, null: false, default: 0
      add :available_count, :integer, null: false, default: 0
      add :availability_percent, :float
      add :report, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:monitoring_probe_runs, [:inserted_at])
    create index(:monitoring_probe_runs, [:status, :inserted_at])
  end
end
