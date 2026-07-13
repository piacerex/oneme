defmodule Oneme.FaceAnalysesTest do
  use Oneme.DataCase

  alias Oneme.FaceAnalyses

  test "stores only derived metadata and builds avatar attributes" do
    assert {:ok, job} =
             FaceAnalyses.create_job(%{
               "analysis" => %{
                 "detected" => true,
                 "colors" => %{"skin" => "#d5a083", "hair" => "#332211"},
                 "faceMorph" => %{"widthScale" => 1.08, "heightScale" => 1.12, "depth" => 0.55},
                 "imageDataUrl" => "data:image/png;base64,should-not-persist"
               }
             })

    assert job.status == "succeeded"
    refute Jason.encode!(job.input_metadata) =~ "imageDataUrl"
    refute Jason.encode!(job.input_metadata) =~ "data:image"

    assert {:ok, attrs} = FaceAnalyses.create_avatar_attrs(job, %{"name" => "Derived avatar"})
    assert attrs.name == "Derived avatar"
    assert attrs.config["colors"]["skin"] == "#d5a083"
    assert attrs.config["faceMorph"]["depth"] == 0.55
  end
end
