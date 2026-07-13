defmodule OnemeWeb.GenerationJobControllerTest do
  use OnemeWeb.ConnCase

  alias Oneme.Access
  alias Oneme.Usage

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

    regenerated =
      build_conn()
      |> post(~p"/api/generation-jobs/#{response["id"]}/regenerate")
      |> json_response(202)

    assert regenerated["id"] != response["id"]
    assert regenerated["status"] == "succeeded"
  end

  test "rejects generation after the authenticated team's quota is exhausted", %{conn: conn} do
    assert {:ok, result, raw_key} =
             Access.bootstrap(%{
               team_name: "Generation quota API",
               team_slug: "generation-quota-api",
               external_id: "generation-quota-owner"
             })

    assert :ok = Usage.record(result.team.id, "generation_requested", 30)

    conn =
      conn
      |> put_req_header("x-oneme-api-key", raw_key)
      |> post("/api/generation-jobs", %{"avatarConfig" => %{}})

    assert json_response(conn, 429)["error"] == "generation_quota_exceeded"
  end
end
