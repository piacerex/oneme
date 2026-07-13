defmodule Oneme.Access.ApiKey do
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(owner admin editor viewer)

  schema "api_keys" do
    field :team_id, :id
    field :name, :string
    field :key_prefix, :string
    field :key_hash, :string
    field :role, :string, default: "editor"
    field :scopes, :map, default: %{}
    field :last_used_at, :utc_datetime
    field :revoked_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(api_key, attrs) do
    api_key
    |> cast(attrs, [
      :team_id,
      :name,
      :key_prefix,
      :key_hash,
      :role,
      :scopes,
      :last_used_at,
      :revoked_at
    ])
    |> validate_required([:team_id, :name, :key_prefix, :key_hash, :role, :scopes])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint(:key_hash)
  end
end
