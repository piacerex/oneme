defmodule Oneme.Generations.ExternalProvider do
  @moduledoc "HTTP JSON adapter for image-aware generation providers."

  @timeout 30_000
  @blocked_keys ~w(faceImageDataUrl facePhotoDataUrl imageDataUrl imageData rawImage photo)

  def generate(input_config) when is_map(input_config) do
    case provider_url() do
      nil ->
        {:error, :not_configured}

      url ->
        Application.ensure_all_started(:inets)
        Application.ensure_all_started(:ssl)
        request(url, sanitize(input_config))
    end
  end

  defp request(url, input_config) do
    headers =
      [{~c"content-type", ~c"application/json"}]
      |> maybe_authorization()

    body =
      Jason.encode!(%{
        "kind" => "face_candidates",
        "avatarConfig" => input_config
      })

    case :httpc.request(
           :post,
           {String.to_charlist(url), headers, ~c"application/json", body},
           [timeout: @timeout, connect_timeout: 5_000],
           body_format: :binary
         ) do
      {:ok, {{_version, status, _reason}, _response_headers, response_body}}
      when status in 200..299 ->
        decode_response(response_body)

      {:ok, {{_version, status, _reason}, _response_headers, response_body}} ->
        {:error, :provider_http_error,
         "provider responded with HTTP #{status}: #{truncate(response_body)}"}

      {:error, reason} ->
        {:error, :provider_request_failed, inspect(reason)}
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
