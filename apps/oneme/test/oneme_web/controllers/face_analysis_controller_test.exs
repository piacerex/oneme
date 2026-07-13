defmodule OnemeWeb.FaceAnalysisControllerTest do
  use OnemeWeb.ConnCase

  test "creates a face analysis job without persisting source image data", %{conn: conn} do
    response =
      conn
      |> post("/api/face-analysis-jobs", %{
        "analysis" => %{
          "detected" => true,
          "colors" => %{"skin" => "#d5a083", "hair" => "#332211"},
          "faceMorph" => %{"widthScale" => 1.08},
          "imageDataUrl" => "data:image/png;base64,secret"
        }
      })
      |> json_response(202)

    assert response["status"] == "succeeded"
    assert response["result"]["colors"]["skin"] == "#d5a083"
    refute Jason.encode!(response) =~ "imageDataUrl"
    refute Jason.encode!(response) =~ "data:image"
  end

  test "creates an avatar from a completed analysis job", %{conn: conn} do
    job =
      conn
      |> post("/api/face-analysis-jobs", %{
        "analysis" => %{"detected" => true, "colors" => %{"skin" => "#d5a083"}}
      })
      |> json_response(202)

    avatar =
      build_conn()
      |> post("/api/avatars/from-face-analysis", %{
        "faceAnalysisJobId" => job["id"],
        "name" => "Analysis avatar"
      })
      |> json_response(201)

    assert avatar["name"] == "Analysis avatar"
    assert avatar["config"]["colors"]["skin"] == "#d5a083"
  end
end
