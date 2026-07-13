defmodule Oneme.Repo.Migrations.CreateGenerationJobs do
  use Ecto.Migration

  def change do
    create table(:generation_jobs) do
      add :kind, :string, null: false
      add :input_config, :map, null: false, default: %{}
      add :status, :string, null: false, default: "queued"
      add :candidates, :map, null: false, default: %{}
      add :attempts, :integer, null: false, default: 0
      add :error_code, :string
      add :error_message, :text
      add :finished_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:generation_jobs, [:kind, :inserted_at])
    create index(:generation_jobs, [:status])
  end
end
