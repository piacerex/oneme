defmodule Oneme.AssetsTest do
  use Oneme.DataCase

  alias Oneme.Assets

  test "loads seeded parts and their asset contract from the database" do
    parts = Assets.list_parts()
    face = Enum.find(parts, &(&1.part_id == "face.soft_01"))
    asset = Assets.get_asset!(face.asset_key)

    assert length(parts) >= 18
    assert face.slot == "face"
    assert asset.asset_type == "procedural"
    assert asset.origin == %{"x" => 0.0, "y" => 0.0, "z" => 0.0}
    assert asset.scale == 1.0
    assert asset.redistributable == true

    assert Assets.form_parts()[:face] == [
             {"Soft", "face.soft_01"},
             {"Sharp", "face.sharp_01"},
             {"Round", "face.round_01"}
           ]
  end
end
