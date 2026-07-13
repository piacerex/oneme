defmodule Oneme.Assets.AvatarPart do
  use Ecto.Schema
  import Ecto.Changeset

  schema "avatar_parts" do
    field :slot, :string
    field :part_id, :string
    field :label, :string
    field :asset_key, :string
    field :sort_order, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def changeset(part, attrs) do
    part
    |> cast(attrs, [:slot, :part_id, :label, :asset_key, :sort_order])
    |> validate_required([:slot, :part_id, :label, :asset_key, :sort_order])
  end
end
