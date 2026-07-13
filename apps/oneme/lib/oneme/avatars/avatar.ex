defmodule Oneme.Avatars.Avatar do
  use Ecto.Schema
  import Ecto.Changeset

  schema "avatars" do
    field :name, :string
    field :config, :map
    field :visibility, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(avatar, attrs) do
    avatar
    |> cast(attrs, [:name, :config, :visibility])
    |> validate_required([:name, :config, :visibility])
    |> validate_inclusion(:visibility, ~w(private public))
  end
end
