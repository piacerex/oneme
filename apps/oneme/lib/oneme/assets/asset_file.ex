defmodule Oneme.Assets.AssetFile do
  use Ecto.Schema
  import Ecto.Changeset

  schema "asset_files" do
    field :asset_key, :string
    field :asset_type, :string
    field :source_path, :string
    field :origin, :map, default: %{}
    field :scale, :float, default: 1.0
    field :license_name, :string
    field :license_url, :string
    field :redistributable, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  def changeset(asset, attrs) do
    asset
    |> cast(attrs, [
      :asset_key,
      :asset_type,
      :source_path,
      :origin,
      :scale,
      :license_name,
      :license_url,
      :redistributable
    ])
    |> validate_required([:asset_key, :asset_type, :source_path, :origin, :scale, :license_name])
  end
end
