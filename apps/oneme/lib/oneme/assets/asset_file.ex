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
    field :content_sha256, :string
    field :content_bytes, :integer
    field :inspection_status, :string, default: "pending"
    field :inspection_error, :string
    field :inspected_at, :utc_datetime

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
      :redistributable,
      :content_sha256,
      :content_bytes,
      :inspection_status,
      :inspection_error,
      :inspected_at
    ])
    |> validate_required([:asset_key, :asset_type, :source_path, :origin, :scale, :license_name])
    |> validate_inclusion(:inspection_status, ~w(pending passed failed))
    |> validate_number(:content_bytes, greater_than_or_equal_to: 0)
  end
end
