defmodule Oneme.Access.Team do
  use Ecto.Schema
  import Ecto.Changeset

  schema "teams" do
    field :name, :string
    field :slug, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(team, attrs) do
    team
    |> cast(attrs, [:name, :slug])
    |> validate_required([:name, :slug])
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9-]*$/)
    |> unique_constraint(:slug)
  end
end
