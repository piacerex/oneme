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
      delivery = maybe_deliver(delivery, params)
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

  def retry_delivery(conn, %{"id" => id}) do
    with {:ok, team_id} <- admin_team(conn),
         delivery when not is_nil(delivery) <- Webhooks.get_delivery(id),
         endpoint when not is_nil(endpoint) <- Webhooks.get_endpoint(delivery.webhook_endpoint_id),
         true <- endpoint.team_id == team_id,
         {:ok, delivered} <- Webhooks.deliver(delivery.id) do
      conn |> put_status(:accepted) |> json(Webhooks.serialize_delivery(delivered))
    else
      {:error, :forbidden} ->
        forbidden(conn)

      nil ->
        send_resp(conn, :not_found, "webhook delivery not found")

      false ->
        send_resp(conn, :not_found, "webhook delivery not found")

      {:error, :not_found} ->
        send_resp(conn, :not_found, "webhook delivery not found")

      {:error, :inactive_endpoint} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "inactive_endpoint"})

      {:error, _reason} ->
        conn |> put_status(:bad_gateway) |> json(%{error: "webhook_delivery_failed"})
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

  defp maybe_deliver(delivery, params) do
    if Map.get(params, "deliver") in [true, "true", "1"] do
      case Webhooks.deliver(delivery.id) do
        {:ok, delivered} -> delivered
        _ -> delivery
      end
    else
      delivery
    end
  end

  defp forbidden(conn), do: conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
end
