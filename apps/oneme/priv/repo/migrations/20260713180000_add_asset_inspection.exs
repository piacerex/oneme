defmodule Oneme.Repo.Migrations.AddAssetInspection do
  use Ecto.Migration

  def change do
    alter table(:asset_files) do
      add :content_sha256, :string
      add :content_bytes, :bigint
      add :inspection_status, :string, null: false, default: "pending"
      add :inspection_error, :text
      add :inspected_at, :utc_datetime
    end

    create index(:asset_files, [:inspection_status])
  end
end
