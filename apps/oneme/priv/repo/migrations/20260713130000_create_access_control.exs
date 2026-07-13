defmodule Oneme.Repo.Migrations.CreateAccessControl do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :external_id, :string, null: false
      add :email, :string, null: false
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:external_id])
    create unique_index(:users, [:email])

    create table(:teams) do
      add :name, :string, null: false
      add :slug, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:teams, [:slug])

    create table(:team_members) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :role, :string, null: false, default: "viewer"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:team_members, [:team_id, :user_id])
    create index(:team_members, [:user_id])

    create table(:api_keys) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :key_prefix, :string, null: false
      add :key_hash, :string, null: false
      add :role, :string, null: false, default: "editor"
      add :scopes, :map, null: false, default: %{}
      add :last_used_at, :utc_datetime
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:api_keys, [:key_hash])
    create index(:api_keys, [:team_id, :revoked_at])

    alter table(:avatars) do
      add :team_id, references(:teams, on_delete: :nilify_all)
    end

    create index(:avatars, [:team_id])
  end
end
