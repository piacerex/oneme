defmodule OnemeWeb.WebhookControllerTest do
  use OnemeWeb.ConnCase

  alias Oneme.Access

  test "admin can create, list, and queue a signed webhook delivery", %{conn: conn} do
    assert {:ok, result, raw_key} =
             Access.bootstrap(%{
               team_name: "Webhook API team",
               team_slug: "webhook-api-team",
               external_id: "webhook-api-owner"
             })

    response =
      conn
      |> put_req_header("authorization", "Bearer #{raw_key}")
      |> post("/api/webhooks", %{
        "name" => "Events",
        "url" => "https://example.com/hooks",
        "events" => ["avatar.exported"]
      })
      |> json_response(201)

    assert response["webhook"]["teamId"] == result.team.id
    assert String.starts_with?(response["secret"], "whsec_")
    assert response["webhook"]["secret"] == nil

    list =
      build_conn()
      |> put_req_header("x-oneme-api-key", raw_key)
      |> get("/api/webhooks")
      |> json_response(200)

    assert length(list["webhooks"]) == 1
    assert list["webhooks"] |> hd() |> Map.has_key?("secret") == false

    delivery =
      build_conn()
      |> put_req_header("x-oneme-api-key", raw_key)
      |> post("/api/webhooks/#{response["webhook"]["id"]}/test", %{
        "event" => "avatar.exported",
        "payload" => %{"avatarId" => 42}
      })
      |> json_response(202)

    assert delivery["status"] == "queued"
    assert String.starts_with?(delivery["signature"], "sha256=")
  end
end
