defmodule Oneme.Repo.Migrations.CreateAvatars do
  use Ecto.Migration

  def change do
    create table(:avatars) do
      add :name, :string, null: false
      add :config, :map, null: false, default: %{}
      add :visibility, :string, null: false, default: "private"

      timestamps(type: :utc_datetime)
    end

    create index(:avatars, [:inserted_at])
  end
end
