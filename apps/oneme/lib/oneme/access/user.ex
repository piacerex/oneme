defmodule Oneme.Access.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :external_id, :string
    field :email, :string
    field :name, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:external_id, :email, :name])
    |> validate_required([:external_id, :email, :name])
    |> validate_format(:email, ~r/@/)
    |> unique_constraint(:external_id)
    |> unique_constraint(:email)
  end
end
