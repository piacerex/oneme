defmodule Oneme.AssetsIntegrityTest do
  use Oneme.DataCase

  alias Oneme.Assets

  test "reports procedural catalog sources and licenses as healthy" do
    report = Assets.integrity_report()

    assert report.status == "ok"
    assert report.assetCount >= 18
    assert report.reviewCount == 0
    assert Enum.all?(report.assets, &(&1.status == "ok"))
  end
end
