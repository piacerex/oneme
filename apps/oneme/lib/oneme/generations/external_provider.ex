defmodule Oneme.Generations.ExternalProvider do
  @moduledoc "HTTP JSON adapter for image-aware generation providers."

  @api_version "v1"
  @default_timeout 30_000
  @default_connect_timeout 5_000
  @default_max_attempts 2
  @default_retry_delay_ms 250
  @blocked_keys ~w(faceImageDataUrl facePhotoDataUrl imageDataUrl imageData rawImage photo)

  def generate(input_config, request_id \\ nil) when is_map(input_config) do
    request_id = normalize_request_id(request_id)

    case provider_url() do
      nil ->
        {:error, :not_configured}

      url ->
        Application.ensure_all_started(:inets)
        Application.ensure_all_started(:ssl)
        request(url, sanitize(input_config), request_id)
    end
  end

  defp request(url, input_config, request_id), do: request(url, input_config, request_id, 1)

  defp request(url, input_config, request_id, attempt) do
    headers =
      [
        {~c"content-type", ~c"application/json"},
        {~c"x-oneme-api-version", String.to_charlist(@api_version)}
      ]
      |> maybe_authorization()
      |> maybe_request_id(request_id)

    body =
      Jason.encode!(%{
        "kind" => "face_candidates",
        "avatarConfig" => input_config
      })

    case :httpc.request(
           :post,
           {String.to_charlist(url), headers, ~c"application/json", body},
           [timeout: timeout_ms(), connect_timeout: connect_timeout_ms()],
           body_format: :binary
         ) do
      {:ok, {{_version, status, _reason}, _response_headers, response_body}}
      when status in 200..299 ->
        with {:ok, response} <- decode_response(response_body) do
          {:ok, put_request_metadata(response, request_id)}
        end

      {:ok, {{_version, status, _reason}, _response_headers, response_body}} ->
        if retryable?(request_id, attempt, status) do
          retry_after_delay()
          request(url, input_config, request_id, attempt + 1)
        else
          {:error, :provider_http_error,
           "provider responded with HTTP #{status}: #{truncate(response_body)}"}
        end

      {:error, reason} ->
        if retryable?(request_id, attempt, reason) do
          retry_after_delay()
          request(url, input_config, request_id, attempt + 1)
        else
          {:error, :provider_request_failed, inspect(reason)}
        end
    end
  rescue
    error -> {:error, :provider_request_failed, Exception.message(error)}
  end

  defp decode_response(response_body) do
    with {:ok, payload} <- Jason.decode(response_body),
         candidates when is_list(candidates) <- Map.get(payload, "candidates"),
         true <- candidates != [],
         :ok <- moderation_result(payload) do
      {:ok,
       %{
         provider: provider_name(payload),
         candidates: Enum.take(candidates, 3),
         metadata: response_metadata(payload)
       }}
    else
      {:error, %Jason.DecodeError{}} ->
        {:error, :provider_invalid_json, "provider returned invalid JSON"}

      nil ->
        {:error, :provider_invalid_response, "provider response has no candidates list"}

      false ->
        {:error, :provider_invalid_response, "provider returned no candidates"}

      {:error, code, message} ->
        {:error, code, message}

      _ ->
        {:error, :provider_invalid_response, "provider response is not an object"}
    end
  end

  defp moderation_result(payload) do
    case moderation_status(payload) do
      status when status in ["blocked", "rejected", "failed"] ->
        {:error, :content_moderation_blocked,
         "provider moderation rejected the generated candidate."}

      nil ->
        if require_moderation?() do
          {:error, :moderation_required, "provider moderation result is required."}
        else
          :ok
        end

      _status ->
        :ok
    end
  end

  defp moderation_status(payload) do
    moderation = Map.get(payload, "moderation", %{})

    if is_map(moderation) do
      case Map.get(moderation, "status") do
        status when is_binary(status) -> String.downcase(status)
        _ -> nil
      end
    end
  end

  defp response_metadata(payload) do
    usage = Map.get(payload, "usage", %{})
    moderation = Map.get(payload, "moderation", %{})
    usage = if is_map(usage), do: usage, else: %{}
    moderation = if is_map(moderation), do: moderation, else: %{}

    %{}
    |> put_integer("inputTokens", Map.get(usage, "inputTokens"))
    |> put_integer("outputTokens", Map.get(usage, "outputTokens"))
    |> put_integer("costCents", Map.get(usage, "costCents"))
    |> put_text("moderationProvider", Map.get(moderation, "provider"))
    |> put_text("moderationStatus", moderation_status(payload))
  end

  defp provider_name(payload) do
    case Map.get(payload, "provider") do
      provider when is_binary(provider) and provider != "" -> String.slice(provider, 0, 100)
      _ -> "external_http"
    end
  end

  defp put_integer(metadata, _key, value) when not is_integer(value), do: metadata
  defp put_integer(metadata, key, value), do: Map.put(metadata, key, value)

  defp put_text(metadata, _key, value) when not is_binary(value) or value == "", do: metadata
  defp put_text(metadata, key, value), do: Map.put(metadata, key, String.slice(value, 0, 100))

  defp require_moderation? do
    System.get_env("ONEME_GENERATION_REQUIRE_MODERATION", "false") in ["1", "true"]
  end

  defp provider_url do
    case System.get_env("ONEME_GENERATION_PROVIDER_URL") do
      url when is_binary(url) and url != "" ->
        if valid_url?(url), do: url, else: nil

      _ ->
        nil
    end
  end

  defp valid_url?(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) -> true
      %URI{scheme: "http", host: host} when is_binary(host) -> insecure_http_allowed?(host)
      _ -> false
    end
  end

  defp insecure_http_allowed?(host) do
    host in ["localhost", "127.0.0.1"] and
      System.get_env("ONEME_GENERATION_ALLOW_INSECURE_HTTP", "false") in ["1", "true"]
  end

  defp maybe_authorization(headers) do
    case System.get_env("ONEME_GENERATION_PROVIDER_API_KEY") do
      key when is_binary(key) and key != "" ->
        headers ++ [{~c"authorization", String.to_charlist("Bearer " <> key)}]

      _ ->
        headers
    end
  end

  defp maybe_request_id(headers, nil), do: headers

  defp maybe_request_id(headers, request_id) do
    value = String.to_charlist(request_id)
    headers ++ [{~c"x-oneme-request-id", value}, {~c"idempotency-key", value}]
  end

  defp put_request_metadata(response, nil), do: response

  defp put_request_metadata(%{metadata: metadata} = response, request_id) do
    %{response | metadata: Map.put(metadata, "requestId", request_id)}
  end

  defp normalize_request_id(value) when is_binary(value) do
    value = String.trim(value)

    if value == "" or String.contains?(value, "\r") or String.contains?(value, "\n") do
      nil
    else
      String.slice(value, 0, 128)
    end
  end

  defp normalize_request_id(_value), do: nil

  defp retryable_status?(status) when is_integer(status),
    do: status in [408, 425, 429] or status >= 500

  defp retryable_status?(_status), do: false

  defp retryable?(request_id, attempt, reason_or_status) do
    is_binary(request_id) and attempt < max_attempts() and
      (retryable_status?(reason_or_status) or retryable_reason?(reason_or_status))
  end

  defp retryable_reason?(reason) do
    reason in [:timeout, :closed, :econnreset, :econnrefused] or
      match?({:failed_connect, _}, reason) or
      match?({:shutdown, _}, reason)
  end

  defp retry_after_delay do
    case integer_env("ONEME_GENERATION_RETRY_DELAY_MS", @default_retry_delay_ms, 0, 5_000) do
      0 -> :ok
      delay -> Process.sleep(delay)
    end
  end

  defp timeout_ms,
    do: integer_env("ONEME_GENERATION_TIMEOUT_MS", @default_timeout, 1_000, 120_000)

  defp connect_timeout_ms,
    do: integer_env("ONEME_GENERATION_CONNECT_TIMEOUT_MS", @default_connect_timeout, 500, 30_000)

  defp max_attempts,
    do: integer_env("ONEME_GENERATION_MAX_ATTEMPTS", @default_max_attempts, 1, 5)

  defp integer_env(name, default, min, max) do
    case Integer.parse(System.get_env(name, Integer.to_string(default))) do
      {value, ""} when value >= min and value <= max -> value
      _ -> default
    end
  end

  defp truncate(value) when is_binary(value), do: String.slice(value, 0, 500)
  defp truncate(value), do: inspect(value) |> String.slice(0, 500)

  defp sanitize(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested}, acc ->
      if to_string(key) in @blocked_keys do
        acc
      else
        Map.put(acc, key, sanitize(nested))
      end
    end)
  end

  defp sanitize(value) when is_list(value), do: Enum.map(value, &sanitize/1)
  defp sanitize(value), do: value
end
