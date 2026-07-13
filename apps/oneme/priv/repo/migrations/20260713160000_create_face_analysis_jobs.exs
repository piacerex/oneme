defmodule Oneme.Repo.Migrations.CreateFaceAnalysisJobs do
  use Ecto.Migration

  def change do
    create table(:face_analysis_jobs) do
      add :status, :string, null: false, default: "queued"
      add :input_metadata, :map, null: false, default: %{}
      add :result, :map, null: false, default: %{}
      add :attempts, :integer, null: false, default: 0
      add :error_code, :string
      add :error_message, :text
      add :expires_at, :utc_datetime, null: false
      add :consumed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:face_analysis_jobs, [:status, :expires_at])
  end
end
