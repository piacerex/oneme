defmodule Oneme.Billing.CheckoutProvider do
  @moduledoc "HTTP JSON adapter for provider-hosted subscription checkout sessions."

  @api_version "v1"
  @default_timeout 30_000
  @default_connect_timeout 5_000
  @default_max_attempts 2
  @default_retry_delay_ms 250

  def create(payload, idempotency_key) when is_map(payload) do
    case {provider_url(), normalize_idempotency_key(idempotency_key)} do
      {nil, _} ->
        {:error, :not_configured}

      {_url, nil} ->
        {:error, :idempotency_key_required}

      {url, key} ->
        Application.ensure_all_started(:inets)
        Application.ensure_all_started(:ssl)
        request(url, payload, key, 1)
    end
  end

  def create(_payload, _idempotency_key), do: {:error, :invalid_request}

  defp request(url, payload, idempotency_key, attempt) do
    headers = [
      {~c"content-type", ~c"application/json"},
      {~c"x-oneme-api-version", String.to_charlist(@api_version)},
      {~c"x-oneme-request-id", String.to_charlist(idempotency_key)},
      {~c"idempotency-key", String.to_charlist(idempotency_key)}
    ]

    headers = maybe_authorization(headers)

    case :httpc.request(
           :post,
           {String.to_charlist(url), headers, ~c"application/json",
            Jason.encode!(sanitize_payload(payload))},
           [timeout: timeout_ms(), connect_timeout: connect_timeout_ms()],
           body_format: :binary
         ) do
      {:ok, {{_version, status, _reason}, _response_headers, response_body}}
      when status in 200..299 ->
        decode_response(response_body)

      {:ok, {{_version, status, _reason}, _response_headers, response_body}} ->
        if retryable?(status, attempt) do
          retry_after_delay()
          request(url, payload, idempotency_key, attempt + 1)
        else
          {:error, :provider_http_error,
           "billing provider responded with HTTP #{status}: #{truncate(response_body)}"}
        end

      {:error, reason} ->
        if retryable?(reason, attempt) do
          retry_after_delay()
          request(url, payload, idempotency_key, attempt + 1)
        else
          {:error, :provider_request_failed, inspect(reason)}
        end
    end
  rescue
    error -> {:error, :provider_request_failed, Exception.message(error)}
  end

  defp decode_response(response_body) do
    with {:ok, payload} <- Jason.decode(response_body),
         true <- is_map(payload),
         provider when is_binary(provider) <- text_value(payload, ["provider"]),
         session_id when is_binary(session_id) <- text_value(payload, ["sessionId", "id"]),
         checkout_url when is_binary(checkout_url) <-
           secure_url(payload, ["checkoutUrl", "url"]) do
      {:ok,
       %{
         provider: String.slice(provider, 0, 100),
         session_id: String.slice(session_id, 0, 200),
         checkout_url: checkout_url,
         status: text_value(payload, ["status"]) || "pending"
       }}
    else
      {:error, %Jason.DecodeError{}} ->
        {:error, :provider_invalid_json, "billing provider returned invalid JSON"}

      nil ->
        {:error, :provider_invalid_response, "billing provider response is missing a field"}

      false ->
        {:error, :provider_invalid_response, "billing provider response is not an object"}

      _ ->
        {:error, :provider_invalid_response, "billing provider response is invalid"}
    end
  end

  defp text_value(payload, keys) do
    Enum.find_value(keys, fn key ->
      case Map.get(payload, key) do
        value when is_binary(value) and value != "" -> value
        _ -> nil
      end
    end)
  end

  defp sanitize_payload(payload) do
    plan = Map.get(payload, "plan", %{})

    %{
      "kind" => Map.get(payload, "kind"),
      "teamId" => Map.get(payload, "teamId"),
      "plan" =>
        if is_map(plan) do
          Map.take(plan, ["slug", "currency", "monthlyPriceCents"])
        else
          %{}
        end,
      "successUrl" => Map.get(payload, "successUrl"),
      "cancelUrl" => Map.get(payload, "cancelUrl")
    }
  end

  defp secure_url(payload, keys) do
    case text_value(payload, keys) do
      value ->
        case URI.parse(value) do
          %URI{scheme: "https", host: host} when is_binary(host) and host != "" ->
            String.slice(value, 0, 2_000)

          _ ->
            nil
        end
    end
  end

  defp provider_url do
    case System.get_env("ONEME_BILLING_CHECKOUT_URL") do
      url when is_binary(url) and url != "" ->
        if valid_provider_url?(url), do: url, else: nil

      _ ->
        nil
    end
  end

  defp valid_provider_url?(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) and host != "" ->
        true

      %URI{scheme: "http", host: host} when host in ["localhost", "127.0.0.1"] ->
        System.get_env("ONEME_BILLING_ALLOW_INSECURE_HTTP", "false") in ["1", "true"]

      _ ->
        false
    end
  end

  defp maybe_authorization(headers) do
    case System.get_env("ONEME_BILLING_CHECKOUT_API_KEY") do
      key when is_binary(key) and key != "" ->
        headers ++ [{~c"authorization", String.to_charlist("Bearer " <> key)}]

      _ ->
        headers
    end
  end

  defp normalize_idempotency_key(value) when is_binary(value) do
    value = String.trim(value)

    if value == "" or String.contains?(value, "\r") or String.contains?(value, "\n") do
      nil
    else
      String.slice(value, 0, 128)
    end
  end

  defp normalize_idempotency_key(_value), do: nil

  defp retryable?(status, attempt) when is_integer(status),
    do: attempt < max_attempts() and (status in [408, 425, 429] or status >= 500)

  defp retryable?(reason, attempt) do
    attempt < max_attempts() and
      (reason in [:timeout, :closed, :econnreset, :econnrefused] or
         match?({:failed_connect, _}, reason) or match?({:shutdown, _}, reason))
  end

  defp retry_after_delay do
    case integer_env("ONEME_BILLING_CHECKOUT_RETRY_DELAY_MS", @default_retry_delay_ms, 0, 5_000) do
      0 -> :ok
      delay -> Process.sleep(delay)
    end
  end

  defp timeout_ms,
    do: integer_env("ONEME_BILLING_CHECKOUT_TIMEOUT_MS", @default_timeout, 1_000, 120_000)

  defp connect_timeout_ms,
    do:
      integer_env(
        "ONEME_BILLING_CHECKOUT_CONNECT_TIMEOUT_MS",
        @default_connect_timeout,
        500,
        30_000
      )

  defp max_attempts,
    do: integer_env("ONEME_BILLING_CHECKOUT_MAX_ATTEMPTS", @default_max_attempts, 1, 5)

  defp integer_env(name, default, min, max) do
    case Integer.parse(System.get_env(name, Integer.to_string(default))) do
      {value, ""} when value >= min and value <= max -> value
      _ -> default
    end
  end

  defp truncate(value) when is_binary(value), do: String.slice(value, 0, 500)
  defp truncate(value), do: inspect(value) |> String.slice(0, 500)
end
