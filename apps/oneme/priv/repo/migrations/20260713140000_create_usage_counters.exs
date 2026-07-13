defmodule Oneme.Repo.Migrations.CreateUsageCounters do
  use Ecto.Migration

  def change do
    create table(:usage_counters) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :period_start, :date, null: false
      add :metric, :string, null: false
      add :quantity, :bigint, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:usage_counters, [:team_id, :period_start, :metric])
    create index(:usage_counters, [:team_id, :period_start])
  end
end
