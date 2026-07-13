defmodule Oneme.AssetInspectionTest do
  use Oneme.DataCase

  alias Oneme.Assets
  alias Oneme.Assets.AssetFile
  alias Oneme.Repo

  test "hashes and validates a real GLB file" do
    path = Path.join(System.tmp_dir!(), "oneme-asset-#{System.unique_integer([:positive])}.glb")
    File.write!(path, <<"glTF", 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, asset} =
             %AssetFile{}
             |> AssetFile.changeset(%{
               asset_key: "fixture.glb",
               asset_type: "glb",
               source_path: path,
               origin: %{},
               scale: 1.0,
               license_name: "test"
             })
             |> Repo.insert()

    assert {:ok, inspected} = Assets.inspect_asset(asset.asset_key)
    assert inspected.inspection_status == "passed"
    assert inspected.content_bytes == 15
    assert String.length(inspected.content_sha256) == 64
    assert inspected.inspection_error == nil
  end

  test "records a failed inspection for a corrupt GLB file" do
    path = Path.join(System.tmp_dir!(), "oneme-corrupt-#{System.unique_integer([:positive])}.glb")
    File.write!(path, "not a glb")
    on_exit(fn -> File.rm(path) end)

    assert {:ok, asset} =
             %AssetFile{}
             |> AssetFile.changeset(%{
               asset_key: "corrupt.glb",
               asset_type: "glb",
               source_path: path,
               origin: %{},
               scale: 1.0,
               license_name: "test"
             })
             |> Repo.insert()

    assert {:ok, inspected} = Assets.inspect_asset(asset.asset_key)
    assert inspected.inspection_status == "failed"
    assert inspected.inspection_error
  end
end
