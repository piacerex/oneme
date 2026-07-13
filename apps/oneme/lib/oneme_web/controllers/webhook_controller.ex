defmodule OnemeWeb.WebhookController do
  use OnemeWeb, :controller

  alias Oneme.Access
  alias Oneme.Webhooks

  def index(conn, _params) do
    with {:ok, team_id} <- admin_team(conn) do
      json(conn, %{
        webhooks: Enum.map(Webhooks.list_endpoints(team_id), &Webhooks.serialize_endpoint/1)
      })
    else
      {:error, :forbidden} -> forbidden(conn)
    end
  end

  def create(conn, params) do
    with {:ok, team_id} <- admin_team(conn),
         {:ok, endpoint, raw_secret} <- Webhooks.create_endpoint(team_id, params) do
      conn
      |> put_status(:created)
      |> json(%{webhook: Webhooks.serialize_endpoint(endpoint), secret: raw_secret})
    else
      {:error, :forbidden} ->
        forbidden(conn)

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(changeset.errors)})
    end
  end

  def test_delivery(conn, %{"id" => id} = params) do
    with {:ok, team_id} <- admin_team(conn),
         %{team_id: ^team_id} = endpoint <- Webhooks.get_endpoint(id),
         {:ok, delivery} <-
           Webhooks.create_test_delivery(
             endpoint,
             Map.get(params, "event", "avatar.exported"),
             Map.get(params, "payload", %{})
           ) do
      conn |> put_status(:accepted) |> json(Webhooks.serialize_delivery(delivery))
    else
      {:error, :forbidden} ->
        forbidden(conn)

      nil ->
        send_resp(conn, :not_found, "webhook not found")

      {:error, :inactive_endpoint} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "inactive_endpoint"})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(changeset.errors)})
    end
  end

  defp admin_team(conn) do
    case conn.assigns[:principal] do
      %{team_id: team_id} = principal when is_integer(team_id) ->
        if Access.authorized?(principal, "admin"), do: {:ok, team_id}, else: {:error, :forbidden}

      _ ->
        {:error, :forbidden}
    end
  end

  defp forbidden(conn), do: conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
end
