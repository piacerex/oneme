defmodule Oneme.Access.TeamMember do
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(owner admin editor viewer)

  schema "team_members" do
    field :team_id, :id
    field :user_id, :id
    field :role, :string, default: "viewer"

    timestamps(type: :utc_datetime)
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:team_id, :user_id, :role])
    |> validate_required([:team_id, :user_id, :role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:team_id, :user_id])
  end
end
