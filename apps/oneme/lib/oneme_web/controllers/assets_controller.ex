defmodule OnemeWeb.AssetsController do
  use OnemeWeb, :controller

  alias Oneme.Access
  alias Oneme.Assets

  def index(conn, _params) do
    parts =
      Enum.map(Assets.list_parts(), fn part ->
        asset = Assets.get_asset!(part.asset_key)

        %{
          slot: part.slot,
          partId: part.part_id,
          label: part.label,
          sortOrder: part.sort_order,
          asset: %{
            key: asset.asset_key,
            type: asset.asset_type,
            sourcePath: asset.source_path,
            origin: asset.origin,
            scale: asset.scale,
            licenseName: asset.license_name,
            licenseUrl: asset.license_url,
            redistributable: asset.redistributable
          }
        }
      end)

    conn |> json(%{parts: parts})
  end

  def integrity(conn, _params) do
    case conn.assigns[:principal] do
      principal when is_map(principal) ->
        if Access.authorized?(principal, "admin"),
          do: json(conn, Assets.integrity_report()),
          else: forbidden(conn)

      _ ->
        forbidden(conn)
    end
  end

  def inspect_asset(conn, %{"asset_key" => asset_key}) do
    with :ok <- admin?(conn),
         {:ok, asset} <- Assets.inspect_asset(asset_key) do
      json(conn, %{asset: serialize_asset(asset)})
    else
      {:error, :forbidden} ->
        forbidden(conn)

      {:error, :not_found} ->
        send_resp(conn, :not_found, "asset not found")

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(changeset.errors)})
    end
  end

  def inspect_all(conn, _params) do
    with :ok <- admin?(conn) do
      json(conn, %{assets: Enum.map(Assets.inspect_all(), &serialize_asset/1)})
    else
      {:error, :forbidden} -> forbidden(conn)
    end
  end

  defp serialize_asset(asset) do
    %{
      assetKey: asset.asset_key,
      sourcePath: asset.source_path,
      inspectionStatus: asset.inspection_status,
      inspectionError: asset.inspection_error,
      contentSha256: asset.content_sha256,
      contentBytes: asset.content_bytes,
      inspectedAt: asset.inspected_at
    }
  end

  defp admin?(conn) do
    case conn.assigns[:principal] do
      principal when is_map(principal) ->
        if Access.authorized?(principal, "admin"), do: :ok, else: {:error, :forbidden}

      _ ->
        {:error, :forbidden}
    end
  end

  defp forbidden(conn), do: conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
end
