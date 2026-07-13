defmodule Oneme.Webhooks do
  @moduledoc "Webhook endpoint registration and signed delivery records."

  import Ecto.Query

  alias Oneme.Repo
  alias Oneme.Webhooks.{WebhookDelivery, WebhookEndpoint}

  def create_endpoint(team_id, attrs) do
    raw_secret = "whsec_" <> Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

    changes = %{
      team_id: team_id,
      name: Map.get(attrs, "name", Map.get(attrs, :name, "oneme webhook")),
      url: Map.get(attrs, "url", Map.get(attrs, :url, "")),
      events: Map.get(attrs, "events", Map.get(attrs, :events, [])),
      secret_prefix: String.slice(raw_secret, 0, 14),
      secret_ciphertext: encrypt_secret(raw_secret),
      active: Map.get(attrs, "active", Map.get(attrs, :active, true))
    }

    case %WebhookEndpoint{} |> WebhookEndpoint.changeset(changes) |> Repo.insert() do
      {:ok, endpoint} -> {:ok, endpoint, raw_secret}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def list_endpoints(team_id) do
    WebhookEndpoint
    |> where([endpoint], endpoint.team_id == ^team_id)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  def get_endpoint(id), do: Repo.get(WebhookEndpoint, id)
  def get_delivery(id), do: Repo.get(WebhookDelivery, id)

  def create_test_delivery(%WebhookEndpoint{active: true} = endpoint, event_type, payload)
      when is_binary(event_type) and is_map(payload) do
    event_id = Ecto.UUID.generate()
    body = Jason.encode!(payload)
    signature = sign(decrypt_secret(endpoint.secret_ciphertext), body)

    changes = %{
      webhook_endpoint_id: endpoint.id,
      event_type: event_type,
      event_id: event_id,
      payload: payload,
      status: "queued",
      attempts: 0,
      signature: signature
    }

    case %WebhookDelivery{} |> WebhookDelivery.changeset(changes) |> Repo.insert() do
      {:ok, delivery} -> {:ok, delivery}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def create_test_delivery(_endpoint, _event_type, _payload), do: {:error, :inactive_endpoint}

  def deliver(id) do
    case Repo.get(WebhookDelivery, id) do
      nil ->
        {:error, :not_found}

      delivery ->
        endpoint = Repo.get!(WebhookEndpoint, delivery.webhook_endpoint_id)
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        {:ok, delivery} =
          delivery
          |> WebhookDelivery.changeset(%{status: "delivering", attempts: delivery.attempts + 1})
          |> Repo.update()

        result = send_request(endpoint, delivery)
        finish_delivery(delivery, endpoint, result, now)
    end
  end

  def list_deliveries(endpoint_id) do
    WebhookDelivery
    |> where([delivery], delivery.webhook_endpoint_id == ^endpoint_id)
    |> order_by(desc: :inserted_at)
    |> limit(50)
    |> Repo.all()
  end

  def serialize_endpoint(endpoint) do
    %{
      id: endpoint.id,
      teamId: endpoint.team_id,
      name: endpoint.name,
      url: endpoint.url,
      events: endpoint.events,
      secretPrefix: endpoint.secret_prefix,
      active: endpoint.active,
      lastDeliveredAt: endpoint.last_delivered_at,
      createdAt: endpoint.inserted_at
    }
  end

  def serialize_delivery(delivery) do
    %{
      id: delivery.id,
      endpointId: delivery.webhook_endpoint_id,
      eventType: delivery.event_type,
      eventId: delivery.event_id,
      status: delivery.status,
      attempts: delivery.attempts,
      signature: delivery.signature,
      responseStatus: delivery.response_status,
      errorMessage: delivery.error_message,
      createdAt: delivery.inserted_at,
      deliveredAt: delivery.delivered_at
    }
  end

  defp sign(secret, body),
    do: "sha256=" <> (:crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower))

  defp send_request(endpoint, delivery) do
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)
    body = Jason.encode!(delivery.payload)
    url = String.to_charlist(endpoint.url)

    headers = [
      {~c"content-type", ~c"application/json"},
      {~c"x-oneme-event", String.to_charlist(delivery.event_type)},
      {~c"x-oneme-event-id", String.to_charlist(delivery.event_id)},
      {~c"x-oneme-signature", String.to_charlist(delivery.signature)}
    ]

    case :httpc.request(
           :post,
           {url, headers, ~c"application/json", body},
           [timeout: 5_000, connect_timeout: 2_000],
           body_format: :binary
         ) do
      {:ok, {{_version, status, _reason}, _response_headers, _response_body}}
      when status in 200..299 ->
        {:ok, status}

      {:ok, {{_version, status, _reason}, _response_headers, _response_body}} ->
        {:error, "webhook responded with HTTP #{status}", status}

      {:error, reason} ->
        {:error, "webhook request failed: #{inspect(reason)}", nil}
    end
  rescue
    error -> {:error, "webhook request failed: #{Exception.message(error)}", nil}
  end

  defp finish_delivery(delivery, endpoint, {:ok, status}, now) do
    {:ok, updated} =
      delivery
      |> WebhookDelivery.changeset(%{
        status: "succeeded",
        response_status: status,
        delivered_at: now
      })
      |> Repo.update()

    endpoint
    |> WebhookEndpoint.changeset(%{last_delivered_at: now})
    |> Repo.update()

    {:ok, updated}
  end

  defp finish_delivery(delivery, _endpoint, {:error, message, status}, now) do
    delivery
    |> WebhookDelivery.changeset(%{
      status: "failed",
      response_status: status,
      error_message: String.slice(message, 0, 500),
      delivered_at: now
    })
    |> Repo.update()
  end

  defp encrypt_secret(secret) do
    Plug.Crypto.encrypt(key_base(), "oneme-webhook-secret", secret, max_age: :infinity)
  end

  defp decrypt_secret(ciphertext) do
    case Plug.Crypto.decrypt(key_base(), "oneme-webhook-secret", ciphertext, max_age: :infinity) do
      {:ok, secret} -> secret
      _ -> raise "webhook secret cannot be decrypted"
    end
  end

  defp key_base do
    System.get_env("ONEME_WEBHOOK_ENCRYPTION_KEY") ||
      Application.get_env(:oneme, OnemeWeb.Endpoint)[:secret_key_base] ||
      "oneme-development-webhook-key"
  end
end
