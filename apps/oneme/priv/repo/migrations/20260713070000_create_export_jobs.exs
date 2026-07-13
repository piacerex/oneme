defmodule Oneme.Repo.Migrations.CreateExportJobs do
  use Ecto.Migration

  def change do
    create table(:export_jobs) do
      add :avatar_config, :map, null: false
      add :format, :string, null: false
      add :status, :string, null: false, default: "queued"
      add :model_path, :string
      add :cache_key, :string, null: false
      add :includes_face_texture, :boolean, null: false, default: false
      add :error_code, :string
      add :error_message, :text
      add :finished_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:export_jobs, [:cache_key])
    create index(:export_jobs, [:status])
  end
end
