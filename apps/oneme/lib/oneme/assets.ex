defmodule Oneme.Assets do
  @moduledoc "Asset and avatar-part catalog backed by PostgreSQL."

  import Ecto.Query

  alias Oneme.Assets.{AssetFile, AvatarPart}
  alias Oneme.Repo

  @repo_url "https://github.com/piacerex/oneme"
  @hash_chunk_size 65_536
  @default_max_asset_bytes 200 * 1024 * 1024
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

  def inspect_asset(asset_key) when is_binary(asset_key) do
    case Repo.get_by(AssetFile, asset_key: asset_key) do
      nil ->
        {:error, :not_found}

      asset ->
        attrs = inspection_attrs(asset)

        case asset |> AssetFile.changeset(attrs) |> Repo.update() do
          {:ok, updated} -> {:ok, updated}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  def inspect_all do
    ensure_seeded()

    Repo.all(from asset in AssetFile, order_by: [asc: asset.asset_key])
    |> Enum.map(fn asset ->
      case inspect_asset(asset.asset_key) do
        {:ok, inspected} -> inspected
        {:error, _reason} -> Repo.get!(AssetFile, asset.id)
      end
    end)
  end

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
          contentSha256: asset.content_sha256,
          contentBytes: asset.content_bytes,
          inspectionStatus: asset.inspection_status,
          inspectionError: asset.inspection_error,
          inspectedAt: asset.inspected_at,
          licenseValid: license_ok,
          status:
            if(source_ok and license_ok and inspection_ok?(asset),
              do: "ok",
              else: "review"
            )
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

  defp inspection_ok?(%AssetFile{asset_type: "procedural"}), do: true
  defp inspection_ok?(%AssetFile{inspection_status: "passed"}), do: true
  defp inspection_ok?(_asset), do: false

  defp inspection_attrs(%AssetFile{asset_type: "procedural"}) do
    %{
      content_sha256: nil,
      content_bytes: nil,
      inspection_status: "passed",
      inspection_error: nil,
      inspected_at: inspection_time()
    }
  end

  defp inspection_attrs(asset) do
    case inspect_source(asset) do
      {:ok, digest, bytes} ->
        %{
          content_sha256: digest,
          content_bytes: bytes,
          inspection_status: "passed",
          inspection_error: nil,
          inspected_at: inspection_time()
        }

      {:error, reason} ->
        %{
          content_sha256: nil,
          content_bytes: file_size(asset.source_path),
          inspection_status: "failed",
          inspection_error: String.slice(to_string(reason), 0, 500),
          inspected_at: inspection_time()
        }
    end
  end

  defp inspect_source(%AssetFile{source_path: path} = asset) do
    with {:ok, stat} <- File.stat(path),
         :ok <- validate_size(stat.size),
         {:ok, digest, bytes, header} <- hash_file(path),
         :ok <- validate_format(asset, header) do
      {:ok, digest, bytes}
    end
  end

  defp validate_size(bytes) when is_integer(bytes) do
    if bytes <= max_asset_bytes(), do: :ok, else: {:error, "asset exceeds maximum allowed size"}
  end

  defp validate_size(_bytes), do: {:error, "asset size is unavailable"}

  defp max_asset_bytes do
    case Integer.parse(System.get_env("ONEME_MAX_ASSET_BYTES", "#{@default_max_asset_bytes}")) do
      {value, ""} when value > 0 -> value
      _ -> @default_max_asset_bytes
    end
  end

  defp hash_file(path) do
    case File.open(path, [:read, :binary]) do
      {:ok, device} ->
        try do
          read_file(device, :crypto.hash_init(:sha256), 0, <<>>)
        after
          File.close(device)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_file(device, context, bytes, header) do
    case IO.binread(device, @hash_chunk_size) do
      :eof ->
        {:ok, :crypto.hash_final(context) |> Base.encode16(case: :lower), bytes, header}

      {:error, reason} ->
        {:error, reason}

      chunk when is_binary(chunk) ->
        combined = header <> chunk
        next_header = binary_part(combined, 0, min(byte_size(combined), 64))

        read_file(
          device,
          :crypto.hash_update(context, chunk),
          bytes + byte_size(chunk),
          next_header
        )
    end
  end

  defp validate_format(%AssetFile{asset_type: "glb", source_path: path}, header) do
    valid =
      Path.extname(path) |> String.downcase() == ".glb" and
        binary_part(header, 0, min(byte_size(header), 4)) == "glTF"

    if valid, do: :ok, else: {:error, "GLB header or extension is invalid"}
  end

  defp validate_format(%AssetFile{asset_type: "fbx", source_path: path}, header) do
    binary = binary_part(header, 0, min(byte_size(header), 23))
    ascii = String.contains?(header, "FBXHeaderExtension")

    valid =
      Path.extname(path) |> String.downcase() == ".fbx" and
        (String.starts_with?(binary, "Kaydara FBX Binary") or ascii)

    if valid, do: :ok, else: {:error, "FBX header or extension is invalid"}
  end

  defp validate_format(%AssetFile{asset_type: "texture", source_path: path}, header) do
    png =
      byte_size(header) >= 8 and
        binary_part(header, 0, 8) == <<137, 80, 78, 71, 13, 10, 26, 10>>

    jpeg = byte_size(header) >= 3 and binary_part(header, 0, 3) == <<255, 216, 255>>

    extension = Path.extname(path) |> String.downcase()
    valid = extension in [".png", ".jpg", ".jpeg"] and (png or jpeg)

    if valid, do: :ok, else: {:error, "texture header or extension is invalid"}
  end

  defp validate_format(_asset, _header), do: :ok

  defp file_size(path) do
    case File.stat(path) do
      {:ok, stat} -> stat.size
      _ -> nil
    end
  end

  defp inspection_time, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
