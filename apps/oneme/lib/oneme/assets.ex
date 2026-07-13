defmodule Oneme.Assets do
  @moduledoc "Asset and avatar-part catalog backed by PostgreSQL."

  import Ecto.Query

  alias Oneme.Assets.{AssetFile, AvatarPart}
  alias Oneme.Repo

  @repo_url "https://github.com/piacerex/oneme"
  @slot_atoms %{
    "baseBody" => :baseBody,
    "face" => :face,
    "hair" => :hair,
    "top" => :top,
    "bottom" => :bottom,
    "shoes" => :shoes,
    "accessory" => :accessory
  }

  @default_parts [
    {"baseBody", "body.basic_01", "Basic Body", 0},
    {"face", "face.soft_01", "Soft", 0},
    {"face", "face.sharp_01", "Sharp", 1},
    {"face", "face.round_01", "Round", 2},
    {"hair", "hair.short_01", "Short", 0},
    {"hair", "hair.bob_01", "Bob", 1},
    {"hair", "hair.long_01", "Long", 2},
    {"top", "top.basic_01", "Basic", 0},
    {"top", "top.hoodie_01", "Hoodie", 1},
    {"top", "top.jacket_01", "Jacket", 2},
    {"bottom", "bottom.basic_01", "Basic", 0},
    {"bottom", "bottom.tapered_01", "Tapered", 1},
    {"bottom", "bottom.skirt_01", "Skirt", 2},
    {"shoes", "shoes.basic_01", "Basic", 0},
    {"shoes", "shoes.sneaker_01", "Sneaker", 1},
    {"shoes", "shoes.boot_01", "Boot", 2},
    {"accessory", "accessory.none", "None", 0},
    {"accessory", "accessory.glasses_01", "Glasses", 1}
  ]

  def list_parts do
    ensure_seeded()
    Repo.all(from part in AvatarPart, order_by: [asc: part.slot, asc: part.sort_order])
  end

  def form_parts do
    list_parts()
    |> Enum.group_by(& &1.slot)
    |> Map.new(fn {slot, parts} ->
      {Map.fetch!(@slot_atoms, slot), Enum.map(parts, &{&1.label, &1.part_id})}
    end)
  end

  def get_asset!(asset_key), do: Repo.get_by!(AssetFile, asset_key: asset_key)

  def integrity_report do
    ensure_seeded()

    assets =
      Repo.all(from asset in AssetFile, order_by: [asc: asset.asset_key])
      |> Enum.map(fn asset ->
        source_ok = source_available?(asset.source_path)

        license_ok =
          asset.license_name != "" and
            (asset.redistributable == false or is_binary(asset.license_url))

        %{
          assetKey: asset.asset_key,
          sourcePath: asset.source_path,
          sourceAvailable: source_ok,
          licenseValid: license_ok,
          status: if(source_ok and license_ok, do: "ok", else: "review")
        }
      end)

    review_count = Enum.count(assets, &(&1.status == "review"))

    %{
      status: if(review_count == 0, do: "ok", else: "review"),
      assetCount: length(assets),
      reviewCount: review_count,
      assets: assets
    }
  end

  defp ensure_seeded do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    asset_rows =
      @default_parts
      |> Enum.map(fn {_slot, part_id, _label, _sort_order} -> part_id end)
      |> Enum.uniq()
      |> Enum.map(fn asset_key ->
        %{
          asset_key: asset_key,
          asset_type: "procedural",
          source_path: "procedural://#{asset_key}",
          origin: %{"x" => 0.0, "y" => 0.0, "z" => 0.0},
          scale: 1.0,
          license_name: "oneme-demo",
          license_url: @repo_url,
          redistributable: true,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(AssetFile, asset_rows, on_conflict: :nothing, conflict_target: [:asset_key])

    part_rows =
      Enum.map(@default_parts, fn {slot, part_id, label, sort_order} ->
        %{
          slot: slot,
          part_id: part_id,
          label: label,
          asset_key: part_id,
          sort_order: sort_order,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(AvatarPart, part_rows, on_conflict: :nothing, conflict_target: [:part_id])
    :ok
  end

  defp source_available?("procedural://" <> _asset_key), do: true
  defp source_available?(path) when is_binary(path), do: File.exists?(path)
  defp source_available?(_path), do: false
end
