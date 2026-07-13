defmodule OnemeWeb.GenerationJobControllerTest do
  use OnemeWeb.ConnCase

  test "creates and updates candidate generation jobs", %{conn: conn} do
    conn =
      post(conn, ~p"/api/generation-jobs", %{
        "avatarConfig" => %{"faceMorph" => %{"widthScale" => 1.1}}
      })

    response = json_response(conn, 201)
    assert response["status"] == "succeeded"
    assert length(response["candidates"]) == 3

    candidate_id = hd(response["candidates"])["id"]

    response =
      build_conn()
      |> post(~p"/api/generation-jobs/#{response["id"]}/feedback", %{
        "candidateId" => candidate_id,
        "decision" => "adopt"
      })
      |> json_response(200)

    first_candidate = hd(response["candidates"])
    assert first_candidate["status"] == "adopted"
  end
end
