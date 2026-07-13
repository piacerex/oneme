defmodule Oneme.Repo.Migrations.CreateAssetCatalog do
  use Ecto.Migration

  def change do
    create table(:asset_files) do
      add :asset_key, :string, null: false
      add :asset_type, :string, null: false
      add :source_path, :string, null: false
      add :origin, :map, null: false, default: %{}
      add :scale, :float, null: false, default: 1.0
      add :license_name, :string, null: false
      add :license_url, :string
      add :redistributable, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:asset_files, [:asset_key])

    create table(:avatar_parts) do
      add :slot, :string, null: false
      add :part_id, :string, null: false
      add :label, :string, null: false
      add :asset_key, :string, null: false
      add :sort_order, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:avatar_parts, [:part_id])
    create index(:avatar_parts, [:slot, :sort_order])
  end
end
