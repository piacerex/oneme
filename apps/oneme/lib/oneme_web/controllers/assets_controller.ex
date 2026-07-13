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

  defp forbidden(conn), do: conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
end
